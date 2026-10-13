defmodule Bolognesa.Music.Infrastructure.Repositories.EctoImportRepository do
  @moduledoc false
  @behaviour Bolognesa.Music.Application.Ports.Repositories.ImportRepository
  import Ecto.Query

  alias Bolognesa.Infrastructure.Persistence.{
    InspectionSchema,
    LibrarySchema,
    MediaFileSchema,
    MusicImportSchema
  }

  alias Bolognesa.Infrastructure.Persistence.MusicRefreshEventSchema
  alias Bolognesa.Music.Domain.Entities.ImportState
  alias Bolognesa.Music.Infrastructure.Jobs.RefreshWorker
  alias Bolognesa.Repo

  @impl true
  def request_retry(file_id) do
    transaction(fn ->
      case locked(file_id) do
        {:ok, file, inspection, state} -> retry(file, inspection, state)
        :stale -> {:error, :not_found}
      end
    end)
  end

  @impl true
  def begin_attempt(file_id, revision, job_id) do
    transaction(fn ->
      case locked(file_id) do
        {:ok, %{revision: ^revision} = file, inspection, state} ->
          begin(file, inspection, state, job_id)

        _ ->
          {:ok, :stale}
      end
    end)
  end

  @impl true
  def fail_attempt(attempt, reason) do
    transaction(fn ->
      case locked(attempt.media_file_id) do
        {:ok, file, inspection, state} -> fail_current(file, inspection, state, attempt, reason)
        :stale -> {:ok, :stale}
      end
    end)
  end

  defp fail_current(file, inspection, state, attempt, reason) do
    if state && state.job_id == attempt.job_id && state.state != :succeeded &&
         state.inspection_token == attempt.inspection_token &&
         inspection.token == attempt.inspection_token &&
         file.revision == attempt.observed_revision do
      state
      |> MusicImportSchema.changeset(%{
        state: :failed,
        failure_reason: reason,
        finished_at: DateTime.utc_now()
      })
      |> Repo.update!()

      :ok
    else
      {:ok, :stale}
    end
  end

  defp begin(file, inspection, state, job_id) do
    cond do
      state && state.inspection_token == inspection.token && state.state in [:succeeded, :failed] ->
        {:ok, :stale}

      state && state.inspection_token == inspection.token && state.job_id &&
          state.job_id != job_id ->
        {:ok, :stale}

      true ->
        row =
          save(state, %{
            media_file_id: file.id,
            observed_revision: file.revision,
            inspection_token: inspection.token,
            state: :running,
            job_id: job_id,
            failure_reason: nil,
            started_at: DateTime.utc_now(),
            finished_at: nil
          })

        {:ok, to_state(row)}
    end
  end

  defp retry(file, inspection, state) do
    if state && state.inspection_token == inspection.token &&
         state.state in [:pending, :running, :succeeded] do
      :ok
    else
      {:ok, job} =
        Oban.insert(
          RefreshWorker.new(%{
            file_id: file.id,
            revision: file.revision
          })
        )

      save(state, %{
        media_file_id: file.id,
        observed_revision: file.revision,
        inspection_token: inspection.token,
        state: :pending,
        job_id: job.id,
        failure_reason: nil,
        started_at: nil,
        finished_at: nil
      })

      :ok
    end
  end

  defp locked(file_id) do
    file =
      Repo.one(from(row in MediaFileSchema, where: row.id == ^file_id, lock: "FOR UPDATE"),
        log: false
      )

    inspection =
      Repo.one(
        from(row in InspectionSchema, where: row.media_file_id == ^file_id, lock: "FOR UPDATE"),
        log: false
      )

    state =
      Repo.one(
        from(row in MusicImportSchema, where: row.media_file_id == ^file_id, lock: "FOR UPDATE")
      )

    if eligible?(file, inspection), do: {:ok, file, inspection, state}, else: :stale
  end

  defp eligible?(nil, _inspection), do: false
  defp eligible?(_file, nil), do: false

  defp eligible?(file, inspection) do
    file.availability == :available &&
      Repo.get!(LibrarySchema, file.library_id).content_type == :music &&
      inspection.state == :succeeded && inspection.observed_revision == file.revision &&
      Enum.any?(inspection.tracks["items"] || [], &(&1["kind"] == "audio"))
  end

  defp save(nil, attrs),
    do: Repo.insert!(MusicImportSchema.changeset(%MusicImportSchema{}, attrs))

  defp save(state, attrs), do: Repo.update!(MusicImportSchema.changeset(state, attrs))

  defp to_state(row),
    do:
      struct!(
        ImportState,
        Map.take(Map.from_struct(row), Map.keys(Map.from_struct(%ImportState{})))
      )

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
    cutoff = DateTime.add(now, -60, :second)

    ids = Enum.uniq(reconciliation_ids(cutoff) ++ unstarted_ids())

    Enum.reduce_while(ids, :ok, &reconcile_id(&1, cutoff, &2))
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp unstarted_ids do
    Repo.all(
      from(event in MusicRefreshEventSchema,
        join: file in MediaFileSchema,
        on: file.id == event.media_file_id,
        join: library in LibrarySchema,
        on: library.id == file.library_id,
        join: inspection in InspectionSchema,
        on:
          inspection.media_file_id == event.media_file_id and
            inspection.token == event.inspection_token,
        left_join: import_state in MusicImportSchema,
        on:
          import_state.media_file_id == event.media_file_id and
            import_state.inspection_token == event.inspection_token,
        left_join: job in Oban.Job,
        on: job.id == event.job_id,
        where: file.availability == :available,
        where: library.content_type == :music,
        where: inspection.state == :succeeded,
        where: inspection.observed_revision == file.revision,
        where: event.revision == file.revision,
        where: fragment(~s|? @> '{"items":[{"kind":"audio"}]}'::jsonb|, inspection.tracks),
        where: not is_nil(event.delivered_at),
        where: is_nil(import_state.id),
        where: is_nil(job.id) or job.state in ["discarded", "cancelled", "completed"],
        order_by: event.id,
        limit: 100,
        select: event.media_file_id
      )
    )
  end

  defp job(nil), do: nil
  defp job(id), do: Repo.get(Oban.Job, id)

  defp recover_unstarted(file, inspection) do
    event =
      Repo.get_by(MusicRefreshEventSchema,
        media_file_id: file.id,
        inspection_token: inspection.token
      )

    recover_event(file, inspection, event)
  end

  defp recover_event(_file, _inspection, nil), do: :ok
  defp recover_event(_file, _inspection, %{delivered_at: nil}), do: :ok

  defp recover_event(file, inspection, event) do
    case recovery_reason(job(event.job_id), DateTime.utc_now()) do
      reason when reason in [:attempts_exhausted, :unexpected_failure] ->
        existing = Repo.get_by(MusicImportSchema, media_file_id: file.id)

        save(existing, %{
          media_file_id: file.id,
          observed_revision: file.revision,
          inspection_token: inspection.token,
          state: :failed,
          job_id: event.job_id,
          failure_reason: reason,
          finished_at: DateTime.utc_now()
        })

        :ok

      _ ->
        :ok
    end
  end

  defp reconcile_existing(state, inspection, cutoff) do
    if state.inspection_token == inspection.token do
      reconcile_state(state, inspection, cutoff)
    else
      file = Repo.get!(MediaFileSchema, state.media_file_id)
      recover_unstarted(file, inspection)
    end
  end

  defp reconciliation_ids(cutoff) do
    Repo.all(
      from(row in MusicImportSchema,
        join: file in MediaFileSchema,
        on: file.id == row.media_file_id,
        join: library in LibrarySchema,
        on: library.id == file.library_id,
        join: inspection in InspectionSchema,
        on: inspection.media_file_id == file.id,
        where: file.availability == :available,
        where: library.content_type == :music,
        where: inspection.state == :succeeded,
        where: inspection.observed_revision == file.revision,
        where: row.observed_revision == file.revision,
        where: row.inspection_token == inspection.token,
        where: fragment(~s|? @> '{"items":[{"kind":"audio"}]}'::jsonb|, inspection.tracks),
        left_join: job in Oban.Job,
        on: job.id == row.job_id,
        where: row.state in [:pending, :running],
        where:
          is_nil(job.id) or job.state in ["discarded", "cancelled", "completed"] or
            (row.state == :running and job.state in ["retryable", "available"]) or
            (row.state == :running and row.started_at < ^cutoff and job.state == "executing" and
               job.attempted_at < ^cutoff),
        order_by: row.id,
        limit: 100,
        select: row.media_file_id
      )
    )
  end

  defp reconcile_id(id, cutoff, :ok) do
    case transaction(fn -> reconcile(id, cutoff) end) do
      :ok -> {:cont, :ok}
      error -> {:halt, error}
    end
  end

  defp reconcile(id, cutoff) do
    case locked(id) do
      {:ok, _file, inspection, state} when not is_nil(state) ->
        reconcile_existing(state, inspection, cutoff)

      {:ok, file, inspection, nil} ->
        recover_unstarted(file, inspection)

      _ ->
        :ok
    end
  end

  defp reconcile_state(state, inspection, cutoff) do
    if state.state in [:pending, :running] && state.inspection_token == inspection.token do
      update_recovery(state, job(state.job_id), cutoff)
    end

    :ok
  end

  defp update_recovery(state, %{state: status}, _cutoff)
       when status in ["available", "retryable", "scheduled"] do
    save(state, %{state: :pending, started_at: nil})
  end

  defp update_recovery(state, job, cutoff) do
    case recovery_reason(job, cutoff) do
      nil ->
        :ok

      reason ->
        save(state, %{state: :failed, failure_reason: reason, finished_at: DateTime.utc_now()})
    end
  end

  defp recovery_reason(nil, _cutoff), do: :unexpected_failure
  defp recovery_reason(%{state: "discarded"}, _cutoff), do: :attempts_exhausted

  defp recovery_reason(%{state: state}, _cutoff) when state in ["cancelled", "completed"],
    do: :unexpected_failure

  defp recovery_reason(%{state: "executing", attempted_at: attempted}, cutoff)
       when not is_nil(attempted) do
    if DateTime.compare(attempted, cutoff) == :lt, do: :unexpected_failure, else: nil
  end

  defp recovery_reason(_job, _cutoff), do: nil
end
