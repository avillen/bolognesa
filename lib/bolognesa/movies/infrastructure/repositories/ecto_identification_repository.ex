defmodule Bolognesa.Movies.Infrastructure.Repositories.EctoIdentificationRepository do
  alias Ecto.UUID
  @moduledoc false
  import Ecto.Query

  @behaviour Bolognesa.Movies.Application.Ports.Repositories.IdentificationRepository

  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Movies.Domain.Entities.Identification
  alias Bolognesa.Movies.Domain.ReadModels.FileToIdentify
  alias Bolognesa.Movies.Infrastructure.Repositories.EctoIdentificationRepository.DecisionStore
  alias Bolognesa.Movies.Infrastructure.Repositories.EctoIdentificationRepository.ObanJobRecovery
  alias Bolognesa.Movies.Infrastructure.Repositories.EctoIdentificationRepository.RequestWriter
  alias Bolognesa.Movies.Infrastructure.Repositories.IdentificationMapper
  alias Bolognesa.Movies.Infrastructure.Repositories.IdentifiedMovieWriter
  alias Bolognesa.Repo

  @spec request_batch!(Bolognesa.Movies.transaction_repository(), [
          Bolognesa.Movies.request_entry()
        ]) ::
          non_neg_integer()
  def request_batch!(repo, entries), do: RequestWriter.request_batch!(repo, entries)

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
      row -> {:ok, IdentificationMapper.to_domain(row)}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  @impl true
  def begin_identification(file_id, token, job_id) do
    transaction(fn ->
      case current(file_id, token) do
        {:ok, identification, projection} when identification.state == :pending ->
          start_pending_identification(identification, projection, job_id)

        _ ->
          {:ok, :stale}
      end
    end)
  end

  @impl true
  def complete(file_id, token, candidates, details, needs_review) do
    transaction(fn ->
      case current(file_id, token) do
        {:ok, identification, _projection} when identification.state == :pending ->
          complete_pending_identification(identification, candidates, details, needs_review)

        _ ->
          {:ok, :stale}
      end
    end)
  end

  @impl true
  def fail(file_id, token, reason) do
    transaction(fn ->
      case current(file_id, token) do
        {:ok, identification, _projection} when identification.state == :pending ->
          {:ok, failed} =
            Identification.fail(
              IdentificationMapper.to_domain(identification),
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

  @impl true
  def reconcile_jobs_result(now) do
    ObanJobRecovery.interrupted(Repo, now)
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

  defp start_pending_identification(identification, projection, job_id) do
    {:ok, started} =
      Identification.start(
        IdentificationMapper.to_domain(identification),
        job_id,
        DateTime.utc_now()
      )

    DecisionStore.save!(Repo, identification, started)
    {:ok, projection}
  end

  defp complete_pending_identification(identification, candidates, details, needs_review) do
    movie_id = if details, do: IdentifiedMovieWriter.upsert!(details), else: nil
    complete_decision!(identification, movie_id, candidates, needs_review)
    :ok
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
      if choice == :unidentified, do: nil, else: IdentifiedMovieWriter.upsert!(choice)

    save_correction(identification, file, movie_id)
  end

  defp request_retry(file) do
    RequestWriter.request_batch!(Repo, [
      %{file_id: file.id, revision: file.revision, requested?: true}
    ])

    get(file.id)
  end

  defp current(file_id, token) do
    file =
      Repo.one(from(row in MediaFileSchema, where: row.id == ^file_id, lock: "FOR UPDATE"),
        log: false
      )

    identification = DecisionStore.lock(Repo, file_id)
    projection = file && file_projection(file)

    if projection && projection.content_type == :movie && identification &&
         identification.token == token &&
         identification.origin != :manual && file.availability == :available &&
         file.revision == identification.observed_revision,
       do: {:ok, identification, projection},
       else: :stale
  end

  defp candidate_data(candidate) do
    candidate |> Map.from_struct() |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp complete_decision!(row, ids, candidates, needs_review) do
    result = %{
      candidate_data: %{"items" => Enum.map(Enum.take(candidates, 5), &candidate_data/1)},
      needs_review?: needs_review,
      failure_reason: nil
    }

    {:ok, completed} =
      Identification.complete(
        IdentificationMapper.to_domain(row),
        ids,
        result,
        DateTime.utc_now()
      )

    DecisionStore.save!(Repo, row, completed)
  end

  defp save_correction(existing, file, ids) do
    token = UUID.generate()
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

  defp correction_base(existing, _file, _token), do: IdentificationMapper.to_domain(existing)

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
  end
end
