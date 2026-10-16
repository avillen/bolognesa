defmodule Bolognesa.Series.Infrastructure.Repositories.EctoIdentificationRepository do
  @moduledoc false
  import Ecto.Query

  @behaviour Bolognesa.Series.Application.Ports.Repositories.IdentificationRepository

  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Repo
  alias Bolognesa.Series.Domain.Entities.Identification
  alias Bolognesa.Series.Domain.ReadModels.FileToIdentify
  alias Bolognesa.Series.Infrastructure.Repositories.EctoIdentificationRepository.DecisionStore
  alias Bolognesa.Series.Infrastructure.Repositories.EctoIdentificationRepository.EntryStore
  alias Bolognesa.Series.Infrastructure.Repositories.EctoIdentificationRepository.JobRecovery
  alias Bolognesa.Series.Infrastructure.Repositories.EctoRequestWriter
  alias Bolognesa.Series.Infrastructure.Repositories.IdentificationMapper
  alias Bolognesa.Series.Infrastructure.Repositories.IdentifiedSeriesWriter

  @impl true
  def find_file(id) do
    case Repo.get(MediaFileSchema, id, log: false) do
      %{availability: :available} = file -> {:ok, file_projection(file)}
      _ -> {:error, :not_found}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  @impl true
  def complete_series(file_id, token, candidates, selection, reason) do
    transaction(fn ->
      case current(file_id, token) do
        {:ok, identification, file} when identification.state == :pending ->
          complete_series_current(identification, file, candidates, selection, reason)

        _ ->
          {:ok, :stale}
      end
    end)
  end

  @impl true
  def correct_series(file_id, expected_revision, choice) do
    transaction(fn ->
      file = Repo.one(from row in MediaFileSchema, where: row.id == ^file_id, lock: "FOR UPDATE")
      correct_series_current(file, expected_revision, choice)
    end)
  end

  defp complete_series_current(identification, file, candidates, selection, reason) do
    if file_projection(file).content_type == :series do
      ids = if selection, do: IdentifiedSeriesWriter.upsert!(selection), else: []

      complete_decision!(identification, ids, candidates, ids == [], reason)
      :ok
    else
      {:ok, :stale}
    end
  end

  defp correct_series_current(nil, _revision, _choice), do: {:error, :not_found}

  defp correct_series_current(file, expected_revision, choice) do
    cond do
      file.availability != :available -> {:error, :not_found}
      file.revision != expected_revision -> {:error, :source_changed}
      file_projection(file).content_type != :series -> {:error, :wrong_content_type}
      true -> save_series_correction(file, choice)
    end
  end

  defp save_series_correction(file, choice) do
    existing = DecisionStore.lock(Repo, file.id)
    ids = if choice == :unidentified, do: [], else: IdentifiedSeriesWriter.upsert!(choice)
    save_correction(existing, file, ids)
  end

  defp file_projection(file) do
    library = Repo.get!(LibrarySchema, file.library_id, log: false)

    %FileToIdentify{
      relative_path: file.relative_path,
      revision: file.revision,
      content_type: library.content_type
    }
  end

  @spec get(pos_integer()) ::
          {:ok, Identification.t()} | {:error, :not_found | :unavailable}
  def get(file_id) do
    case DecisionStore.get(Repo, file_id) do
      nil -> {:error, :not_found}
      row -> {:ok, decision(row)}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  @spec begin_identification(pos_integer(), Identification.token(), integer() | nil) ::
          {:ok, :stale} | {:ok, FileToIdentify.t()} | {:error, :unavailable}
  @impl true
  def begin_identification(file_id, token, job_id) do
    transaction(fn ->
      case current(file_id, token) do
        {:ok, identification, file} when identification.state == :pending ->
          start_pending_identification(identification, file, job_id)

        _ ->
          {:ok, :stale}
      end
    end)
  end

  @spec fail(pos_integer(), Identification.token(), atom()) ::
          :ok | {:ok, :stale} | {:error, :unavailable}
  @impl true
  def fail(file_id, token, reason) do
    transaction(fn ->
      case current(file_id, token) do
        {:ok, identification, _file} when identification.state == :pending ->
          {:ok, failed} =
            Identification.fail(
              decision(identification),
              Atom.to_string(reason),
              DateTime.utc_now()
            )

          DecisionStore.save!(Repo, identification, failed)

          :ok

        _ ->
          {:ok, :stale}
      end
    end)
  end

  @spec retry(pos_integer()) ::
          {:ok, Identification.t()} | {:error, :not_found | :manual_locked | :unavailable}
  @impl true
  def retry(file_id) do
    transaction(fn ->
      file =
        Repo.one(from(row in MediaFileSchema, where: row.id == ^file_id, lock: "FOR UPDATE"),
          log: false
        )

      identification = DecisionStore.lock(Repo, file_id)

      cond do
        is_nil(file) ->
          {:error, :not_found}

        file.availability != :available ->
          {:error, :not_found}

        file_projection(file).content_type != :series ->
          {:error, :wrong_content_type}

        identification && identification.origin == :manual ->
          {:error, :manual_locked}

        true ->
          request_retry(file)
      end
    end)
  end

  @spec reconcile_jobs(DateTime.t()) :: :ok | {:error, :unavailable}
  def reconcile_jobs(now) do
    JobRecovery.interrupted(Repo, now)
    |> Enum.each(fn {file_id, token, state} ->
      reason = if state == "discarded", do: :attempts_exhausted, else: :unexpected_failure
      fail(file_id, token, reason)
    end)

    :ok
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp start_pending_identification(identification, file, job_id) do
    {:ok, started} = Identification.start(decision(identification), job_id, DateTime.utc_now())
    DecisionStore.save!(Repo, identification, started)
    {:ok, file_projection(file)}
  end

  defp request_retry(file) do
    EctoRequestWriter.request_batch!(Repo, [
      %{file_id: file.id, revision: file.revision, requested?: true}
    ])

    case get(file.id) do
      {:ok, identification} -> {:ok, identification}
      error -> error
    end
  end

  defp current(file_id, token) do
    file =
      Repo.one(from(row in MediaFileSchema, where: row.id == ^file_id, lock: "FOR UPDATE"),
        log: false
      )

    identification = DecisionStore.lock(Repo, file_id)

    if file && file_projection(file).content_type == :series && identification &&
         identification.token == token &&
         identification.origin != :manual && file.availability == :available &&
         file.revision == identification.observed_revision,
       do: {:ok, identification, file},
       else: :stale
  end

  defp candidate_data(candidate) do
    candidate |> Map.from_struct() |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp decision(row) do
    IdentificationMapper.to_domain(row, EntryStore.ids(Repo, row.id))
  end

  defp complete_decision!(row, ids, candidates, needs_review, reason) do
    result = %{
      candidate_data: %{"items" => Enum.map(Enum.take(candidates, 5), &candidate_data/1)},
      needs_review?: needs_review,
      failure_reason: if(reason, do: Atom.to_string(reason), else: nil)
    }

    {:ok, completed} = Identification.complete(decision(row), ids, result, DateTime.utc_now())
    saved = DecisionStore.save!(Repo, row, completed)
    EntryStore.replace!(Repo, saved.id, completed.episode_ids)
  end

  defp save_correction(existing, file, ids) do
    token = Ecto.UUID.generate()
    base = correction_base(existing, file, token)
    removed_ids = base.episode_ids -- ids
    {:ok, corrected} = Identification.correct(base, file.revision, token, ids, DateTime.utc_now())
    saved = DecisionStore.save!(Repo, existing, corrected)
    EntryStore.replace!(Repo, saved.id, corrected.episode_ids)
    IdentifiedSeriesWriter.delete_orphaned!(removed_ids)
    {:ok, IdentificationMapper.to_domain(saved, ids)}
  end

  defp correction_base(nil, file, token) do
    {:ok, pending} = Identification.new(file.id, file.revision, token)
    pending
  end

  defp correction_base(existing, _file, _token), do: decision(existing)

  defp transaction(fun) do
    case Repo.transaction(fun) do
      {:ok, value} -> value
      {:error, _} -> {:error, :unavailable}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
    Ecto.ConstraintError -> {:error, :unavailable}
    Ecto.InvalidChangesetError -> {:error, :unavailable}
    MatchError -> {:error, :unavailable}
  end
end
