defmodule Bolognesa.Movies.Infrastructure.Repositories.EctoIdentificationRepository do
  @moduledoc false
  import Ecto.Query

  @behaviour Bolognesa.Movies.Application.Ports.Repositories.IdentificationRepository

  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Movies.Domain.Entities.Identification
  alias Bolognesa.Movies.Domain.ReadModels.FileToIdentify
  alias Bolognesa.Movies.Domain.ValueObjects.MovieCandidate
  alias Bolognesa.Movies.Domain.ValueObjects.MovieDetails
  alias Bolognesa.Movies.Infrastructure.Repositories.EctoIdentificationRepository.DecisionStore
  alias Bolognesa.Movies.Infrastructure.Repositories.EctoIdentificationRepository.JobRecovery
  alias Bolognesa.Movies.Infrastructure.Repositories.EctoRequestWriter
  alias Bolognesa.Movies.Infrastructure.Repositories.IdentificationMapper
  alias Bolognesa.Movies.Infrastructure.Repositories.IdentifiedMovieWriter
  alias Bolognesa.Repo

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

  @spec complete(
          pos_integer(),
          Identification.token(),
          [MovieCandidate.t()],
          MovieDetails.t() | nil,
          boolean()
        ) ::
          :ok | {:ok, :stale} | {:error, :unavailable}
  @impl true
  def complete(file_id, token, candidates, details, needs_review) do
    transaction(fn ->
      case current(file_id, token) do
        {:ok, identification, file} when identification.state == :pending ->
          complete_movie_current(identification, file, candidates, details, needs_review)

        _ ->
          {:ok, :stale}
      end
    end)
  end

  @spec fail(
          pos_integer(),
          Identification.token(),
          Bolognesa.Movies.Application.Ports.Repositories.IdentificationRepository.failure_reason()
        ) ::
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

  @spec correct(pos_integer(), pos_integer(), :unidentified | MovieDetails.t()) ::
          {:ok, Identification.t()} | {:error, :not_found | :unavailable}
  @impl true
  def correct(file_id, expected_revision, choice) do
    transaction(fn ->
      file =
        Repo.one(from(row in MediaFileSchema, where: row.id == ^file_id, lock: "FOR UPDATE"),
          log: false
        )

      if file do
        correct_file(file, file_id, expected_revision, choice)
      else
        {:error, :not_found}
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

        file_projection(file).content_type != :movie ->
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
    case reconcile_jobs_result(now) do
      {:ok, _count} -> :ok
      {:error, :unavailable, _count} -> {:error, :unavailable}
    end
  end

  @spec reconcile_jobs_result(DateTime.t()) ::
          {:ok, non_neg_integer()} | {:error, :unavailable, non_neg_integer()}
  @impl true
  def reconcile_jobs_result(now) do
    JobRecovery.interrupted(Repo, now)
    |> Enum.reduce({:ok, 0}, fn {file_id, token, state}, result ->
      reason = if state == "discarded", do: :attempts_exhausted, else: :unexpected_failure
      recovery_result(fail(file_id, token, reason), result)
    end)
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable, 0}
    Postgrex.Error -> {:error, :unavailable, 0}
  end

  defp recovery_result(:ok, {:ok, count}), do: {:ok, count + 1}
  defp recovery_result(:ok, {:error, :unavailable, count}), do: {:error, :unavailable, count + 1}

  defp recovery_result({:error, :unavailable}, result),
    do: {:error, :unavailable, elem(result, tuple_size(result) - 1)}

  defp recovery_result({:ok, :stale}, result), do: result

  defp start_pending_identification(identification, file, job_id) do
    {:ok, started} = Identification.start(decision(identification), job_id, DateTime.utc_now())
    DecisionStore.save!(Repo, identification, started)
    {:ok, file_projection(file)}
  end

  defp complete_movie_current(identification, file, candidates, details, needs_review) do
    if file_projection(file).content_type == :movie,
      do: complete_pending_identification(identification, candidates, details, needs_review),
      else: {:ok, :stale}
  end

  defp complete_pending_identification(identification, candidates, details, needs_review) do
    movie_id = if details, do: upsert_movie_id(details), else: nil
    complete_decision!(identification, movie_id, candidates, needs_review, nil)
    :ok
  end

  defp upsert_movie_id(details) do
    IdentifiedMovieWriter.upsert!(details)
  end

  defp correct_file(file, file_id, expected_revision, choice) do
    cond do
      file.availability != :available -> {:error, :not_found}
      file_projection(file).content_type != :movie -> {:error, :wrong_content_type}
      file.revision != expected_revision -> {:error, :source_changed}
      true -> correct_movie_file(file, file_id, choice)
    end
  end

  defp correct_movie_file(file, file_id, choice) do
    identification = DecisionStore.lock(Repo, file_id)

    movie_id =
      if choice == :unidentified, do: nil, else: upsert_movie_id(choice)

    save_correction(identification, file, movie_id)
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

    if file && file_projection(file).content_type == :movie && identification &&
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
    IdentificationMapper.to_domain(row)
  end

  defp complete_decision!(row, ids, candidates, needs_review, reason) do
    result = %{
      candidate_data: %{"items" => Enum.map(Enum.take(candidates, 5), &candidate_data/1)},
      needs_review?: needs_review,
      failure_reason: if(reason, do: Atom.to_string(reason), else: nil)
    }

    {:ok, completed} = Identification.complete(decision(row), ids, result, DateTime.utc_now())
    saved = DecisionStore.save!(Repo, row, completed)
    saved
  end

  defp save_correction(existing, file, ids) do
    token = Ecto.UUID.generate()
    base = correction_base(existing, file, token)
    removed_ids = List.wrap(base.movie_id) -- List.wrap(ids)
    {:ok, corrected} = Identification.correct(base, file.revision, token, ids, DateTime.utc_now())
    saved = DecisionStore.save!(Repo, existing, corrected)
    IdentifiedMovieWriter.delete_orphaned!(removed_ids)
    {:ok, IdentificationMapper.to_domain(saved)}
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
