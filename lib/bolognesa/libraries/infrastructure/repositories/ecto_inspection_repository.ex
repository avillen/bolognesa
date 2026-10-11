defmodule Bolognesa.Libraries.Infrastructure.Repositories.EctoInspectionRepository do
  @moduledoc false
  @behaviour Bolognesa.Libraries.Application.Ports.Repositories.InspectionRepository

  import Ecto.Query

  alias Bolognesa.Infrastructure.Persistence.InspectionSchema
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Libraries.Domain.InspectionCounts
  alias Bolognesa.Libraries.Domain.Library
  alias Bolognesa.Libraries.Infrastructure.Jobs.InspectionPolicy
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoInspectionRepository.InspectionMapper
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoScanRepository.MediaFileMapper
  alias Bolognesa.Repo

  @impl true
  def get(file_id) do
    case Repo.get_by(InspectionSchema, media_file_id: file_id) do
      nil -> {:error, :not_found}
      inspection -> {:ok, InspectionMapper.to_inspection(inspection)}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  @impl true
  def counts(library_id) do
    case Repo.get(LibrarySchema, library_id) do
      nil ->
        {:error, :not_found}

      _library ->
        rows =
          Repo.all(
            from file in MediaFileSchema,
              left_join: inspection in InspectionSchema,
              on: inspection.media_file_id == file.id,
              where: file.library_id == ^library_id and file.availability == :available,
              group_by: [inspection.state, inspection.failure_reason],
              select: {inspection.state, inspection.failure_reason, count(file.id)}
          )

        counts = %InspectionCounts{}

        {:ok,
         Enum.reduce(rows, counts, fn {state, reason, count}, acc ->
           acc = Map.update!(acc, state || :uninspected, &(&1 + count))

           if state == :failed do
             Map.update!(
               acc,
               :failure_reasons,
               &Map.update(&1, reason, count, fn total -> total + count end)
             )
           else
             acc
           end
         end)}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  @impl true
  def begin_inspection(file_id, token, job_id) do
    transaction(fn ->
      case current(file_id, token) do
        {:ok, inspection, file} when inspection.state in [:pending, :running] ->
          start_running(inspection, file, job_id)

        _ ->
          {:ok, :stale}
      end
    end)
  end

  @impl true
  def complete_inspection(file_id, token, media) do
    transaction(fn ->
      case current(file_id, token) do
        {:ok, inspection, _file} when inspection.state == :running ->
          tracks = %{"items" => Enum.map(media.tracks, &stringify_track/1)}

          inspection
          |> InspectionSchema.changeset(%{
            state: :succeeded,
            format: media.format,
            duration_ms: media.duration_ms,
            tracks: tracks,
            failure_reason: nil,
            finished_at: DateTime.utc_now()
          })
          |> Repo.update!()

          :ok

        _ ->
          {:ok, :stale}
      end
    end)
  end

  @impl true
  def fail_inspection(file_id, token, reason, _attempt) do
    transaction(fn ->
      case current(file_id, token) do
        {:ok, inspection, _file} when inspection.state in [:pending, :running] ->
          inspection
          |> InspectionSchema.changeset(%{
            state: :failed,
            failure_reason: reason,
            finished_at: DateTime.utc_now()
          })
          |> Repo.update!()

          :ok

        _ ->
          {:ok, :stale}
      end
    end)
  end

  defp current(file_id, token) do
    file = Repo.one(from row in MediaFileSchema, where: row.id == ^file_id, lock: "FOR UPDATE")

    inspection =
      Repo.one(
        from row in InspectionSchema, where: row.media_file_id == ^file_id, lock: "FOR UPDATE"
      )

    if inspection && file && inspection.token == token && file.availability == :available &&
         file.revision == inspection.observed_revision,
       do: {:ok, inspection, file},
       else: :stale
  end

  defp stringify_track(track) do
    track
    |> Map.from_struct()
    |> Map.new(fn {key, value} ->
      {Atom.to_string(key), if(key == :kind, do: Atom.to_string(value), else: value)}
    end)
  end

  defp transaction(operation) do
    case Repo.transaction(operation) do
      {:ok, result} -> result
      {:error, _reason} -> {:error, :unavailable}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
    Ecto.ConstraintError -> {:error, :unavailable}
  end

  @impl true
  def reconcile_jobs(now) do
    cutoff = DateTime.add(now, -InspectionPolicy.rescue_after_ms(), :millisecond)

    ids = reconciliation_ids(cutoff)

    Enum.reduce_while(ids, :ok, fn id, :ok -> reconcile_id(id, cutoff) end)
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp reconcile_id(id, cutoff) do
    case transaction(fn -> reconcile_one(id, cutoff) end) do
      :ok -> {:cont, :ok}
      {:error, :unavailable} = error -> {:halt, error}
    end
  end

  defp start_running(inspection, file, job_id) do
    library = Repo.get!(LibrarySchema, file.library_id)
    attrs = %{state: :running, started_at: DateTime.utc_now()}
    attrs = if job_id, do: Map.put(attrs, :job_id, job_id), else: attrs
    Repo.update!(InspectionSchema.changeset(inspection, attrs))

    {:ok, MediaFileMapper.to_media_file(file),
     %Library{id: library.id, name: library.name, path: library.path}}
  end

  defp reconciliation_ids(cutoff) do
    Repo.all(
      from inspection in InspectionSchema,
        left_join: job in Oban.Job,
        on: job.id == inspection.job_id,
        where: inspection.state in [:pending, :running] and not is_nil(inspection.job_id),
        where:
          is_nil(job.id) or job.state in ["discarded", "cancelled", "completed"] or
            (inspection.state == :running and job.state in ["retryable", "available"]) or
            (inspection.state == :running and job.state == "executing" and
               inspection.started_at < ^cutoff and job.attempted_at < ^cutoff),
        order_by: inspection.id,
        limit: 100,
        select: inspection.id
    )
  end

  defp reconcile_one(id, cutoff) do
    inspection = Repo.one(from row in InspectionSchema, where: row.id == ^id, lock: "FOR UPDATE")

    if inspection && inspection.state in [:pending, :running] do
      reconcile_active(inspection, cutoff)
    end

    :ok
  end

  defp reconcile_active(inspection, cutoff) do
    job = Repo.get(Oban.Job, inspection.job_id)

    if (inspection.state == :running and job) && job.state in ["retryable", "available"] do
      inspection
      |> InspectionSchema.changeset(%{state: :pending, started_at: nil})
      |> Repo.update!()
    else
      fail_if_reason(inspection, job, cutoff)
    end
  end

  defp fail_if_reason(inspection, job, cutoff) do
    case reconciliation_reason(inspection, job, cutoff) do
      nil ->
        :ok

      reason ->
        inspection
        |> InspectionSchema.changeset(%{
          state: :failed,
          failure_reason: reason,
          finished_at: DateTime.utc_now()
        })
        |> Repo.update!()
    end
  end

  defp reconciliation_reason(_inspection, nil, _cutoff), do: :unexpected_failure
  defp reconciliation_reason(_inspection, %{state: "discarded"}, _cutoff), do: :attempts_exhausted

  defp reconciliation_reason(_inspection, %{state: state}, _cutoff)
       when state in ["cancelled", "completed"],
       do: :unexpected_failure

  defp reconciliation_reason(
         %{state: :running, started_at: started},
         %{state: "executing", attempted_at: attempted},
         cutoff
       )
       when not is_nil(started) and not is_nil(attempted) do
    if DateTime.compare(started, cutoff) == :lt and DateTime.compare(attempted, cutoff) == :lt,
      do: :timeout,
      else: nil
  end

  defp reconciliation_reason(_inspection, _job, _cutoff), do: nil
end
