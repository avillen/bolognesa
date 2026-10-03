defmodule Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository do
  @moduledoc false
  @behaviour Bolognesa.Libraries.Application.Ports.ScanRepository

  import Ecto.Query
  alias Bolognesa.Repo
  alias Bolognesa.Libraries.Domain.{MediaFile, Scan, ScanStatus}
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoLibraryRepository.LibrarySchema
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoLibraryRepository.LibraryMapper
  alias __MODULE__.{MediaFileMapper, MediaFileSchema, ScanMapper, ScanSchema}

  @impl true
  def request(library_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:library, fn repo, _changes -> find_library(repo, library_id) end)
    |> Ecto.Multi.insert(
      :scan,
      ScanSchema.changeset(%ScanSchema{}, %{
        library_id: library_id,
        requested_at: DateTime.utc_now()
      })
    )
    |> Oban.insert(:job, fn %{scan: scan} ->
      Oban.Job.new(%{scan_id: scan.id},
        worker: "Bolognesa.Libraries.Infrastructure.Jobs.ScanWorker",
        queue: "library_scans",
        max_attempts: 3
      )
    end)
    |> Ecto.Multi.update(:referenced_scan, fn %{scan: scan, job: job} ->
      ScanSchema.changeset(scan, %{job_id: job.id})
    end)
    |> Repo.transaction()
    |> request_result()
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
    Ecto.ConstraintError -> {:error, :unavailable}
  end

  @impl true
  def status(library_id) do
    with {:ok, _library} <- find_library(Repo, library_id) do
      latest =
        Repo.one(
          from scan in ScanSchema,
            where: scan.library_id == ^library_id,
            order_by: [desc: scan.requested_at, desc: scan.id],
            limit: 1
        )

      last_completed_at =
        Repo.one(
          from scan in ScanSchema,
            where: scan.library_id == ^library_id and scan.state == :completed,
            select: max(scan.finished_at)
        )

      {:ok,
       %ScanStatus{
         library_id: library_id,
         latest_scan: map_latest(latest),
         last_completed_at: last_completed_at
       }}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  @impl true
  def begin_attempt(scan_id, attempt) do
    transaction(fn ->
      scan_id
      |> locked_scan(:not_found)
      |> begin_locked_attempt(attempt)
    end)
  end

  @impl true
  def save_batch(scan_id, generation, entries) do
    transaction(fn ->
      scan = current_attempt!(scan_id, generation)
      entries = Enum.uniq_by(entries, & &1.relative_path)
      existing = load_batch_files(scan.library_id, entries)
      rows = Enum.map(entries, &file_row(scan, Map.get(existing, &1.relative_path), &1))

      Repo.insert_all(MediaFileSchema, rows,
        conflict_target: [:library_id, :relative_path],
        on_conflict:
          {:replace, [:size_bytes, :modified_at, :availability, :revision, :last_seen_generation]}
      )

      added =
        Enum.count(entries, &first_observation?(Map.get(existing, &1.relative_path), generation))

      updated = %{ScanMapper.to_scan(scan) | files_discovered: scan.files_discovered + added}
      {:ok, save_scan(scan, updated)}
    end)
  end

  @impl true
  def complete(scan_id, generation) do
    transaction(fn ->
      scan = current_attempt!(scan_id, generation)
      completed = transition!(scan, :completed, nil)

      Repo.update_all(
        from(file in MediaFileSchema,
          where:
            file.library_id == ^scan.library_id and
              file.last_seen_generation != ^generation
        ),
        set: [availability: :missing]
      )

      {:ok, save_scan(scan, completed)}
    end)
  end

  @impl true
  def fail(scan_id, generation, reason, state) do
    transaction(fn ->
      scan = current_attempt!(scan_id, generation)
      failed = transition!(scan, state, reason)
      _scan = save_scan(scan, failed)
      :ok
    end)
  end

  @impl true
  def reconcile_jobs(_now), do: {:error, :unavailable}

  defp transaction(operation) do
    case Repo.transaction(operation) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
    Ecto.ConstraintError -> {:error, :unavailable}
  end

  defp locked_scan(scan_id, missing_reason) do
    case Repo.one(from scan in ScanSchema, where: scan.id == ^scan_id, lock: "FOR UPDATE") do
      nil -> Repo.rollback(missing_reason)
      scan -> scan
    end
  end

  defp begin_locked_attempt(%ScanSchema{state: state}, _attempt)
       when state in [:completed, :failed],
       do: {:ok, :terminal}

  defp begin_locked_attempt(scan, attempt) do
    library = attempt_library!(scan.library_id)
    running = transition!(scan, :running, nil)
    running = %{running | generation: Ecto.UUID.generate(), attempt: attempt, files_discovered: 0}
    {:ok, save_scan(scan, running), LibraryMapper.to_library(library)}
  end

  defp attempt_library!(library_id) do
    case find_library(Repo, library_id) do
      {:ok, library} -> library
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp current_attempt!(scan_id, generation) do
    scan_id
    |> locked_scan(:stale_attempt)
    |> check_generation!(generation)
  end

  defp check_generation!(%ScanSchema{state: :running, generation: generation} = scan, generation)
       when is_binary(generation),
       do: scan

  defp check_generation!(_scan, _generation), do: Repo.rollback(:stale_attempt)

  defp transition!(scan, state, reason) do
    case Scan.transition(ScanMapper.to_scan(scan), state, reason, DateTime.utc_now()) do
      {:ok, transitioned} -> transitioned
      {:error, :invalid_transition} -> Repo.rollback(:unavailable)
    end
  end

  defp save_scan(schema, scan) do
    attrs =
      Map.take(scan, [
        :state,
        :generation,
        :attempt,
        :files_discovered,
        :failure_reason,
        :started_at,
        :attempt_started_at,
        :finished_at,
        :updated_at
      ])

    case Repo.update(ScanSchema.changeset(schema, attrs)) do
      {:ok, stored} -> ScanMapper.to_scan(stored)
      {:error, _changeset} -> Repo.rollback(:unavailable)
    end
  end

  defp load_batch_files(library_id, entries) do
    paths = Enum.map(entries, & &1.relative_path)

    Repo.all(
      from file in MediaFileSchema,
        where: file.library_id == ^library_id and file.relative_path in ^paths
    )
    |> Map.new(&{&1.relative_path, MediaFileMapper.to_media_file(&1)})
  end

  defp file_row(scan, existing, entry) do
    %{microsecond: {microsecond, _precision}} = entry.modified_at

    %{
      library_id: scan.library_id,
      relative_path: entry.relative_path,
      size_bytes: entry.size_bytes,
      modified_at: %{entry.modified_at | microsecond: {microsecond, 6}},
      availability: :available,
      revision: MediaFile.revision_for(existing, entry),
      last_seen_generation: scan.generation
    }
  end

  defp first_observation?(nil, _generation), do: true
  defp first_observation?(file, generation), do: file.last_seen_generation != generation

  defp find_library(repo, library_id) do
    case repo.get(LibrarySchema, library_id) do
      nil -> {:error, :not_found}
      library -> {:ok, library}
    end
  end

  defp request_result({:ok, %{referenced_scan: scan}}), do: {:ok, ScanMapper.to_scan(scan)}
  defp request_result({:error, :library, :not_found, _changes}), do: {:error, :not_found}

  defp request_result({:error, :scan, changeset, _changes}),
    do: {:error, scan_insert_error(changeset)}

  defp request_result({:error, _step, _reason, _changes}), do: {:error, :unavailable}

  defp scan_insert_error(changeset) do
    if Enum.any?(changeset.errors, fn {_field, {_message, opts}} ->
         opts[:constraint] == :unique and opts[:constraint_name] == "library_scans_one_active"
       end), do: :scan_in_progress, else: :unavailable
  end

  defp map_latest(nil), do: nil
  defp map_latest(scan), do: ScanMapper.to_scan(scan)
end
