defmodule Bolognesa.Libraries.Infrastructure.Repositories.EctoScanRepository do
  alias Ecto.Multi
  alias Ecto.UUID
  @moduledoc false
  @behaviour Bolognesa.Libraries.Application.Ports.Repositories.ScanRepository

  import Ecto.Query

  alias Bolognesa.Infrastructure.Persistence.InspectionSchema
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.ScanSchema
  alias Bolognesa.Libraries.Application.InventoryRequestPlan
  alias Bolognesa.Libraries.Domain.Entities.Scan
  alias Bolognesa.Libraries.Domain.ReadModels.Scans.ScanStatus
  alias Bolognesa.Libraries.Infrastructure.Jobs.Oban.ObanScanJob

  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoInspectionRepository

  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoLibraryRepository.LibraryMapper
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoScanRepository.MediaFileMapper
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoScanRepository.ObanJobRecovery
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoScanRepository.ScanMapper
  alias Bolognesa.Movies
  alias Bolognesa.Repo
  alias Bolognesa.Series

  @impl true
  def request(library_id), do: request(library_id, false)

  @impl true
  def request(library_id, force_inspection?) when is_boolean(force_inspection?) do
    Multi.new()
    |> Multi.run(:library, fn repo, _changes -> find_library(repo, library_id) end)
    |> Multi.insert(
      :scan,
      ScanSchema.changeset(%ScanSchema{}, %{
        library_id: library_id,
        force_inspection: force_inspection?,
        requested_at: DateTime.utc_now()
      })
    )
    |> ObanScanJob.insert()
    |> Multi.update(:referenced_scan, fn %{scan: scan, job: job} ->
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
  def fetch_status(library_id) do
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
      inspections = load_batch_inspections(existing)
      plans = plan_batch(scan, entries, existing, inspections)
      rows = Enum.map(entries, &file_row(scan, &1, Map.fetch!(plans, &1.relative_path)))

      Repo.insert_all(MediaFileSchema, rows,
        log: false,
        conflict_target: [:library_id, :relative_path],
        on_conflict:
          {:replace, [:size_bytes, :modified_at, :availability, :revision, :last_seen_generation]}
      )

      saved = load_batch_files(scan.library_id, entries)
      schedule_inspections(entries, saved, inspections, existing, plans)
      schedule_identifications(scan.library_id, entries, saved, plans)

      added = Enum.count(plans, fn {_path, plan} -> plan.new_discovery? end)

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
  def reconcile_jobs(now), do: ObanJobRecovery.reconcile(now)

  defp transaction(operation) do
    case Repo.transaction(operation) do
      {:ok, result} ->
        result

      {:error, reason} ->
        {:error, reason}
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
    running = %{running | generation: UUID.generate(), attempt: attempt, files_discovered: 0}
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
      from(file in MediaFileSchema,
        where: file.library_id == ^library_id and file.relative_path in ^paths
      ),
      log: false
    )
    |> Map.new(&{&1.relative_path, MediaFileMapper.to_media_file(&1)})
  end

  defp load_batch_inspections(existing) do
    ids = existing |> Map.values() |> Enum.map(& &1.id)

    Repo.all(from(inspection in InspectionSchema, where: inspection.media_file_id in ^ids))
    |> Map.new(&{&1.media_file_id, &1})
  end

  defp plan_batch(scan, entries, existing, inspections) do
    Map.new(entries, fn entry ->
      old = Map.get(existing, entry.relative_path)
      has_inspection? = old != nil and Map.has_key?(inspections, old.id)

      plan =
        InventoryRequestPlan.for_entry(
          old,
          has_inspection?,
          entry,
          scan.force_inspection,
          scan.generation
        )

      {entry.relative_path, plan}
    end)
  end

  defp schedule_inspections(entries, saved, inspections, existing, plans) do
    Enum.each(entries, fn entry ->
      old = Map.get(existing, entry.relative_path)
      file = Map.fetch!(saved, entry.relative_path)
      current_inspection = old && Map.get(inspections, old.id)

      if Map.fetch!(plans, entry.relative_path).inspect? do
        EctoInspectionRepository.enqueue_in_transaction!(file, current_inspection)
      end
    end)
  end

  defp schedule_identifications(library_id, entries, saved, plans) do
    case Repo.get!(LibrarySchema, library_id).content_type do
      :music -> :ok
      :movie -> schedule_video_identifications(Movies, entries, saved, plans)
      :series -> schedule_video_identifications(Series, entries, saved, plans)
    end
  end

  defp schedule_video_identifications(owner, entries, saved, plans) do
    requests =
      Enum.map(entries, fn entry ->
        file = Map.fetch!(saved, entry.relative_path)

        %{
          file_id: file.id,
          revision: file.revision,
          requested?: Map.fetch!(plans, entry.relative_path).identify?
        }
      end)

    owner.request_batch_in_transaction!(Repo, requests)
  end

  defp file_row(scan, entry, plan) do
    %{microsecond: {microsecond, _precision}} = entry.modified_at

    %{
      library_id: scan.library_id,
      relative_path: entry.relative_path,
      size_bytes: entry.size_bytes,
      modified_at: %{entry.modified_at | microsecond: {microsecond, 6}},
      availability: :available,
      revision: plan.revision,
      last_seen_generation: scan.generation
    }
  end

  defp find_library(repo, library_id) do
    case repo.get(LibrarySchema, library_id) do
      nil -> {:error, :not_found}
      library -> {:ok, library}
    end
  end

  defp request_result({:ok, %{referenced_scan: scan}}) do
    {:ok, ScanMapper.to_scan(scan)}
  end

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
