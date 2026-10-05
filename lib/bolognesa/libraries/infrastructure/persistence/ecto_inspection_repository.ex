defmodule Bolognesa.Libraries.Infrastructure.Persistence.EctoInspectionRepository do
  @moduledoc false
  @behaviour Bolognesa.Libraries.Application.Ports.InspectionRepository

  import Ecto.Query

  alias Bolognesa.Libraries.Domain.Library
  alias Bolognesa.Libraries.Infrastructure.Jobs.InspectionPolicy
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoLibraryRepository.LibrarySchema
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository.MediaFileSchema
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository.MediaFileMapper
  alias __MODULE__.InspectionSchema
  alias Bolognesa.Repo

  @impl true
  def get(file_id) do
    case Repo.get_by(InspectionSchema, media_file_id: file_id) do
      nil -> {:error, :not_found}
      inspection -> {:ok, inspection}
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
              group_by: inspection.state,
              select: {inspection.state, count(file.id)}
          )

        counts = %{uninspected: 0, pending: 0, running: 0, succeeded: 0, failed: 0}

        {:ok,
         Enum.reduce(rows, counts, fn {state, count}, acc ->
           Map.put(acc, state || :uninspected, count)
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
          library = Repo.get!(LibrarySchema, file.library_id)
          attrs = %{state: :running, started_at: inspection.started_at || DateTime.utc_now()}
          attrs = if job_id, do: Map.put(attrs, :job_id, job_id), else: attrs
          Repo.update!(InspectionSchema.changeset(inspection, attrs))

          {:ok, MediaFileMapper.to_media_file(file),
           %Library{id: library.id, name: library.name, path: library.path}}

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
    inspection =
      Repo.one(
        from row in InspectionSchema, where: row.media_file_id == ^file_id, lock: "FOR UPDATE"
      )

    file = Repo.get(MediaFileSchema, file_id)

    if inspection && file && inspection.token == token && file.availability == :available &&
         file.revision == inspection.observed_revision,
       do: {:ok, inspection, file},
       else: :stale
  end

  defp stringify_track(track) do
    track
    |> Map.from_struct()
    |> Map.new(fn {key, value} ->
      {Atom.to_string(key), if(is_atom(value), do: Atom.to_string(value), else: value)}
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

    ids =
      Repo.all(
        from inspection in InspectionSchema,
          left_join: job in Oban.Job,
          on: job.id == inspection.job_id,
          where: inspection.state in [:pending, :running] and not is_nil(inspection.job_id),
          where:
            is_nil(job.id) or job.state in ["discarded", "cancelled", "completed"] or
              (inspection.state == :running and inspection.started_at < ^cutoff),
          order_by: inspection.id,
          limit: 100,
          select: inspection.id
      )

    Enum.reduce_while(ids, :ok, fn id, :ok ->
      case transaction(fn -> reconcile_one(id, cutoff) end) do
        :ok -> {:cont, :ok}
        {:error, :unavailable} = error -> {:halt, error}
      end
    end)
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp reconcile_one(id, cutoff) do
    inspection = Repo.one(from row in InspectionSchema, where: row.id == ^id, lock: "FOR UPDATE")

    if inspection && inspection.state in [:pending, :running] do
      job = Repo.get(Oban.Job, inspection.job_id)

      reason =
        cond do
          is_nil(job) ->
            :unexpected_failure

          job.state == "discarded" ->
            :attempts_exhausted

          job.state in ["cancelled", "completed"] ->
            :unexpected_failure

          inspection.state == :running and DateTime.compare(inspection.started_at, cutoff) == :lt ->
            :timeout

          true ->
            nil
        end

      if reason do
        inspection
        |> InspectionSchema.changeset(%{
          state: :failed,
          failure_reason: reason,
          finished_at: DateTime.utc_now()
        })
        |> Repo.update!()
      end
    end

    :ok
  end
end
