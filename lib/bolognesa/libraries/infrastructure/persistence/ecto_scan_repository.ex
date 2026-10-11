defmodule Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository do
  @moduledoc false
  @behaviour Bolognesa.Libraries.Application.Ports.ScanRepository

  import Ecto.Query

  alias Bolognesa.Identification
  alias Bolognesa.Libraries.Application.InventoryRequestPlan
  alias Bolognesa.Libraries.Domain.Scan
  alias Bolognesa.Libraries.Domain.ScanStatus
  alias Bolognesa.Libraries.Infrastructure.Jobs.ScanPolicy
  alias Bolognesa.Libraries.Infrastructure.Jobs.ScanWorker
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoLibraryRepository.LibraryMapper
  alias Bolognesa.Persistence.LibrarySchema
  alias Bolognesa.Repo

  alias Bolognesa.Persistence.InspectionEventSchema
  alias Bolognesa.Persistence.InspectionSchema

  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository.MediaFileMapper
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository.ScanMapper
  alias Bolognesa.Persistence.MediaFileSchema
  alias Bolognesa.Persistence.ScanSchema

  @impl true
  def request(library_id), do: request(library_id, false)

  @impl true
  def request(library_id, force_inspection?) when is_boolean(force_inspection?) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:library, fn repo, _changes -> find_library(repo, library_id) end)
    |> Ecto.Multi.insert(
      :scan,
      ScanSchema.changeset(%ScanSchema{}, %{
        library_id: library_id,
        force_inspection: force_inspection?,
        requested_at: DateTime.utc_now()
      })
    )
    |> Oban.insert(:job, fn %{scan: scan} ->
      ScanWorker.new(%{scan_id: scan.id})
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
      schedule_identifications(entries, saved, plans)

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
  def reconcile_jobs(now) do
    candidates =
      Repo.all(
        from scan in ScanSchema,
          left_join: job in Oban.Job,
          on: job.id == scan.job_id,
          where: scan.state in [:queued, :running, :retrying],
          where:
            is_nil(job.id) or job.state in ["retryable", "discarded", "cancelled", "completed"],
          select: scan.id
      )

    Enum.reduce_while(candidates, :ok, fn id, :ok ->
      reconcile_result(transaction(fn -> reconcile_locked(locked_scan(id, :not_found), now) end))
    end)
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp reconcile_locked(%ScanSchema{state: state}, _now) when state in [:completed, :failed],
    do: :ok

  defp reconcile_locked(scan, now) do
    if attempt_within_budget?(scan, now),
      do: :ok,
      else: reconcile_job(scan, reconciliation_job(scan.job_id), now)
  end

  defp reconciliation_job(nil), do: nil
  defp reconciliation_job(id), do: Repo.get(Oban.Job, id)

  defp attempt_within_budget?(
         %ScanSchema{state: :running, attempt_started_at: %DateTime{} = started},
         now
       ),
       do: DateTime.diff(now, started, :millisecond) < ScanPolicy.timeout_ms()

  defp attempt_within_budget?(_scan, _now), do: false

  defp reconcile_job(scan, nil, now),
    do: reconcile_transition(scan, :failed, :unexpected_failure, now)

  defp reconcile_job(scan, %{state: "discarded"}, now),
    do: reconcile_transition(scan, :failed, :attempts_exhausted, now)

  defp reconcile_job(scan, %{state: state}, now) when state in ["cancelled", "completed"],
    do: reconcile_transition(scan, :failed, :unexpected_failure, now)

  defp reconcile_job(%ScanSchema{state: :retrying}, %{state: "retryable"}, _now), do: :ok

  defp reconcile_job(scan, %{state: "retryable"}, now),
    do: reconcile_transition(scan, :retrying, :unexpected_failure, now)

  defp reconcile_job(_scan, _job, _now), do: :ok

  defp reconcile_transition(scan, state, fallback, now) do
    reason = scan.failure_reason || fallback

    case Scan.transition(ScanMapper.to_scan(scan), state, reason, now) do
      {:ok, transitioned} ->
        _stored = save_scan(scan, transitioned)
        :ok

      _ ->
        Repo.rollback(:unavailable)
    end
  end

  defp reconcile_result(:ok), do: {:cont, :ok}
  defp reconcile_result({:error, :not_found}), do: {:cont, :ok}
  defp reconcile_result({:error, _reason}), do: {:halt, {:error, :unavailable}}

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
        request_inspection!(file, current_inspection)
      end
    end)
  end

  defp request_inspection!(file, current) do
    token = Ecto.UUID.generate()

    attrs = %{
      media_file_id: file.id,
      token: token,
      observed_revision: file.revision,
      state: :pending,
      failure_reason: nil,
      job_id: nil,
      format: nil,
      duration_ms: nil,
      tracks: %{"items" => []},
      started_at: nil,
      finished_at: nil
    }

    case current do
      nil -> Repo.insert!(InspectionSchema.changeset(%InspectionSchema{}, attrs))
      schema -> Repo.update!(InspectionSchema.changeset(schema, attrs))
    end

    Repo.insert!(
      InspectionEventSchema.changeset(%InspectionEventSchema{}, %{
        media_file_id: file.id,
        token: token
      })
    )
  end

  defp schedule_identifications(entries, saved, plans) do
    requests =
      Enum.map(entries, fn entry ->
        file = Map.fetch!(saved, entry.relative_path)

        %{
          file_id: file.id,
          revision: file.revision,
          requested?: Map.fetch!(plans, entry.relative_path).identify?
        }
      end)

    Identification.request_batch_in_transaction!(Repo, requests)
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
