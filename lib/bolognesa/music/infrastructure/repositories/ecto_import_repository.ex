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

  alias Bolognesa.Music.Domain.Entities.ImportState
  alias Bolognesa.Music.Infrastructure.Jobs.RefreshWorker
  alias Bolognesa.Repo

  @spec request_in_transaction!(
          Bolognesa.Music.transaction_repository(),
          Bolognesa.Music.import_request()
        ) ::
          :requested | :unchanged | :stale
  def request_in_transaction!(repo, %{file_id: id, revision: revision, inspection_token: token}) do
    unless repo.in_transaction?(),
      do: raise(ArgumentError, "Music handoff requires a transaction")

    case locked(id, repo) do
      {:ok, %{revision: ^revision} = file, %{token: ^token} = inspection, state} ->
        request_current(repo, file, inspection, state)

      _ ->
        :stale
    end
  end

  defp request_current(_repo, _file, inspection, %{inspection_token: token})
       when token == inspection.token,
       do: :unchanged

  defp request_current(repo, file, inspection, state) do
    write_request(repo, file, inspection, state)
    :requested
  end

  defp write_request(repo, file, inspection, state) do
    row =
      (state || %MusicImportSchema{})
      |> MusicImportSchema.changeset(%{
        media_file_id: file.id,
        observed_revision: file.revision,
        inspection_token: inspection.token,
        state: :pending,
        job_id: nil,
        failure_reason: nil,
        started_at: nil,
        finished_at: nil
      })
      |> repo.insert_or_update!()

    {:ok, %{job: job}} =
      Ecto.Multi.new()
      |> Oban.insert(:job, RefreshWorker.new(%{file_id: file.id, revision: file.revision}))
      |> repo.transaction()

    row |> MusicImportSchema.changeset(%{job_id: job.id}) |> repo.update!()
  end

  @impl true
  def request_retry(file_id) do
    case request_retry_with_result(file_id) do
      {:ok, _result} -> :ok
      error -> error
    end
  end

  @impl true
  def request_retry_with_result(file_id) do
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

  defp begin(_file, _inspection, nil, _job_id), do: {:ok, :stale}

  defp begin(file, inspection, state, job_id) do
    if state.inspection_token == inspection.token and state.observed_revision == file.revision and
         state.job_id == job_id and state.state in [:pending, :running] do
      row =
        save(state, %{
          state: :running,
          failure_reason: nil,
          started_at: DateTime.utc_now(),
          finished_at: nil
        })

      {:ok, to_state(row)}
    else
      {:ok, :stale}
    end
  end

  defp retry(file, inspection, state) do
    if state && state.inspection_token == inspection.token &&
         state.state in [:pending, :running, :succeeded] do
      {:ok, :unchanged}
    else
      write_request(Repo, file, inspection, state)

      {:ok, :requested}
    end
  end

  defp locked(file_id, repo \\ Repo) do
    file =
      repo.one(from(row in MediaFileSchema, where: row.id == ^file_id, lock: "FOR UPDATE"),
        log: false
      )

    inspection =
      repo.one(
        from(row in InspectionSchema, where: row.media_file_id == ^file_id, lock: "FOR UPDATE"),
        log: false
      )

    state =
      repo.one(
        from(row in MusicImportSchema, where: row.media_file_id == ^file_id, lock: "FOR UPDATE")
      )

    if eligible?(file, inspection, repo), do: {:ok, file, inspection, state}, else: :stale
  end

  defp eligible?(nil, _inspection, _repo), do: false
  defp eligible?(_file, nil, _repo), do: false

  defp eligible?(file, inspection, repo) do
    file.availability == :available &&
      repo.get!(LibrarySchema, file.library_id).content_type == :music &&
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
    case reconcile_jobs_with_summary(now) do
      {:ok, _summary} -> :ok
      {:error, :unavailable, _summary} -> {:error, :unavailable}
    end
  end

  @impl true
  def reconcile_jobs_with_summary(now) do
    cutoff = DateTime.add(now, -60, :second)

    ids = reconciliation_ids(cutoff)

    Enum.reduce_while(ids, {:ok, empty_summary()}, &reconcile_id(&1, cutoff, &2))
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable, empty_summary()}
    Postgrex.Error -> {:error, :unavailable, empty_summary()}
  end

  defp empty_summary, do: %{recovered_count: 0, library_ids: []}

  defp job(nil), do: nil
  defp job(id), do: Repo.get(Oban.Job, id)

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

  defp reconcile_id(id, cutoff, {:ok, summary}) do
    case transaction(fn -> reconcile(id, cutoff) end) do
      {:changed, library_id} ->
        updated = %{
          recovered_count: summary.recovered_count + 1,
          library_ids: Enum.uniq([library_id | summary.library_ids])
        }

        {:cont, {:ok, updated}}

      :ok ->
        {:cont, {:ok, summary}}

      {:error, :unavailable} ->
        {:halt, {:error, :unavailable, summary}}
    end
  end

  defp reconcile(id, cutoff) do
    case locked(id) do
      {:ok, file, inspection, state} when not is_nil(state) ->
        reconcile_state(state, inspection, cutoff, file.library_id)

      _ ->
        :ok
    end
  end

  defp reconcile_state(state, inspection, cutoff, library_id) do
    if state.state in [:pending, :running] && state.inspection_token == inspection.token do
      recover_current(state, job(state.job_id), cutoff, library_id)
    else
      :ok
    end
  end

  defp recover_current(state, %{state: status}, _cutoff, library_id)
       when status in ["available", "retryable", "scheduled"] do
    if state.state == :running do
      save(state, %{state: :pending, started_at: nil})
      {:changed, library_id}
    else
      :ok
    end
  end

  defp recover_current(state, job, cutoff, library_id) do
    case recovery_reason(job, cutoff) do
      nil ->
        :ok

      reason ->
        save(state, %{state: :failed, failure_reason: reason, finished_at: DateTime.utc_now()})
        {:changed, library_id}
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
