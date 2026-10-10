defmodule Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository do
  @moduledoc false
  import Ecto.Query

  @behaviour Bolognesa.Identification.Application.Ports.IdentificationRepository
  alias Bolognesa.Catalog
  alias Bolognesa.Identification.Infrastructure.Persistence.IdentificationMapper
  alias Bolognesa.Identification.Infrastructure.Persistence.EctoRequestWriter
  alias Bolognesa.Persistence.MediaFileSchema
  alias Bolognesa.Persistence.IdentificationSchema

  alias Bolognesa.Identification.Domain.{
    FileToIdentify,
    Identification,
    MovieCandidate,
    MovieDetails
  }

  alias Bolognesa.Repo

  @spec get(pos_integer()) ::
          {:ok, Identification.t()} | {:error, :not_found | :unavailable}
  def get(file_id) do
    case Repo.get_by(IdentificationSchema, media_file_id: file_id) do
      nil -> {:error, :not_found}
      row -> {:ok, IdentificationMapper.to_domain(row)}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  @spec begin_identification(pos_integer(), binary(), integer() | nil) ::
          {:ok, :stale} | {:ok, FileToIdentify.t()} | {:error, :unavailable}
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

  @spec complete(pos_integer(), binary(), [MovieCandidate.t()], MovieDetails.t() | nil, boolean()) ::
          :ok | {:ok, :stale} | {:error, :unavailable}
  def complete(file_id, token, candidates, details, needs_review) do
    transaction(fn ->
      case current(file_id, token) do
        {:ok, identification, _file} when identification.state == :pending ->
          complete_pending_identification(identification, candidates, details, needs_review)

        _ ->
          {:ok, :stale}
      end
    end)
  end

  @spec fail(pos_integer(), binary(), atom()) :: :ok | {:ok, :stale} | {:error, :unavailable}
  def fail(file_id, token, reason) do
    transaction(fn ->
      case current(file_id, token) do
        {:ok, identification, _file} when identification.state == :pending ->
          Repo.update!(
            IdentificationSchema.changeset(identification, %{
              state: :failed,
              failure_reason: Atom.to_string(reason),
              needs_review: true,
              finished_at: DateTime.utc_now()
            })
          )

          :ok

        _ ->
          {:ok, :stale}
      end
    end)
  end

  @spec correct(pos_integer(), :unidentified | MovieDetails.t()) ::
          {:ok, Identification.t()} | {:error, :not_found | :unavailable}
  def correct(file_id, choice) do
    transaction(fn ->
      file =
        Repo.one(from(row in MediaFileSchema, where: row.id == ^file_id, lock: "FOR UPDATE"),
          log: false
        )

      if file do
        correct_file(file, file_id, choice)
      else
        {:error, :not_found}
      end
    end)
  end

  @spec retry(pos_integer()) ::
          {:ok, Identification.t()} | {:error, :not_found | :manual_locked | :unavailable}
  def retry(file_id) do
    transaction(fn ->
      file =
        Repo.one(from(row in MediaFileSchema, where: row.id == ^file_id, lock: "FOR UPDATE"),
          log: false
        )

      identification =
        Repo.one(
          from row in IdentificationSchema,
            where: row.media_file_id == ^file_id,
            lock: "FOR UPDATE"
        )

      cond do
        is_nil(file) ->
          {:error, :not_found}

        file.availability != :available ->
          {:error, :not_found}

        identification && identification.origin == :manual ->
          {:error, :manual_locked}

        true ->
          request_retry(file)
      end
    end)
  end

  @spec reconcile_jobs(DateTime.t()) :: :ok | {:error, :unavailable}
  def reconcile_jobs(now) do
    cutoff = DateTime.add(now, -60, :second)

    rows =
      Repo.all(
        from identification in IdentificationSchema,
          left_join: job in Oban.Job,
          on: job.id == identification.job_id,
          where: identification.state == :pending and not is_nil(identification.job_id),
          where:
            is_nil(job.id) or job.state in ["discarded", "cancelled", "completed"] or
              (job.state == "executing" and job.attempted_at < ^cutoff and
                 identification.started_at < ^cutoff),
          order_by: identification.id,
          limit: 100,
          select: {identification.media_file_id, identification.token, job.state}
      )

    Enum.each(rows, fn {file_id, token, state} ->
      reason = if state == "discarded", do: :attempts_exhausted, else: :unexpected_failure
      fail(file_id, token, reason)
    end)

    :ok
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp start_pending_identification(identification, file, job_id) do
    attrs = %{started_at: DateTime.utc_now()}
    attrs = if job_id, do: Map.put(attrs, :job_id, job_id), else: attrs
    Repo.update!(IdentificationSchema.changeset(identification, attrs), log: false)
    {:ok, %FileToIdentify{relative_path: file.relative_path}}
  end

  defp complete_pending_identification(identification, candidates, details, needs_review) do
    movie_id = if details, do: upsert_movie_id(details), else: nil
    state = if movie_id, do: :automatic, else: :unmatched

    attrs = %{
      state: state,
      origin: :automatic,
      movie_id: movie_id,
      needs_review: needs_review,
      failure_reason: nil,
      candidate_data: %{"items" => Enum.map(Enum.take(candidates, 5), &candidate_data/1)},
      finished_at: DateTime.utc_now()
    }

    Repo.update!(IdentificationSchema.changeset(identification, attrs), log: false)
    :ok
  end

  defp upsert_movie_id(details) do
    attrs = details |> Map.from_struct() |> Map.put(:provider, :tmdb)
    Catalog.upsert_in_transaction!(Repo, attrs)
  end

  defp correct_file(file, file_id, choice) do
    identification =
      Repo.one(
        from row in IdentificationSchema,
          where: row.media_file_id == ^file_id,
          lock: "FOR UPDATE"
      )

    movie_id =
      if choice == :unidentified, do: nil, else: upsert_movie_id(choice)

    attrs = %{
      media_file_id: file_id,
      observed_revision: file.revision,
      token: Ecto.UUID.generate(),
      state: if(movie_id, do: :manual, else: :manual_unidentified),
      origin: :manual,
      movie_id: movie_id,
      needs_review: false,
      failure_reason: nil,
      candidate_data: %{"items" => []},
      job_id: nil,
      started_at: nil,
      finished_at: DateTime.utc_now()
    }

    row =
      Repo.insert_or_update!(
        IdentificationSchema.changeset(identification || %IdentificationSchema{}, attrs),
        log: false
      )

    {:ok, IdentificationMapper.to_domain(row)}
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

    identification =
      Repo.one(
        from row in IdentificationSchema, where: row.media_file_id == ^file_id, lock: "FOR UPDATE"
      )

    if file && identification && identification.token == token &&
         identification.origin != :manual && file.availability == :available &&
         file.revision == identification.observed_revision,
       do: {:ok, identification, file},
       else: :stale
  end

  defp candidate_data(candidate) do
    candidate |> Map.from_struct() |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp transaction(fun) do
    case Repo.transaction(fun) do
      {:ok, value} -> value
      {:error, _} -> {:error, :unavailable}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
    Ecto.ConstraintError -> {:error, :unavailable}
  end
end
