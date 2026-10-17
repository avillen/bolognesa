defmodule Bolognesa.Movies.Infrastructure.Repositories.EctoRequestWriter do
  @moduledoc "Writes identification requests in the inventory transaction."

  import Ecto.Query

  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Movies.Domain.Entities.Identification
  alias Bolognesa.Movies.Infrastructure.Jobs.IdentificationWorker
  alias Bolognesa.Movies.Infrastructure.Repositories.EctoIdentificationRepository.DecisionStore
  alias Bolognesa.Movies.Infrastructure.Repositories.IdentificationMapper
  alias Bolognesa.Repo

  @type request_entry :: %{
          required(:file_id) => pos_integer(),
          required(:revision) => pos_integer(),
          required(:requested?) => boolean()
        }

  @spec request_batch!(DecisionStore.repo(), [request_entry()]) :: non_neg_integer()
  def request_batch!(repo, entries) do
    unless repo.in_transaction?(),
      do: raise(ArgumentError, "Identification handoff requires a transaction")

    Enum.count(entries, fn entry ->
      if entry.requested?, do: request_one!(repo, entry.file_id, entry.revision), else: false
    end)
  end

  @spec backfill_batch(non_neg_integer(), pos_integer()) ::
          {:ok, non_neg_integer(), non_neg_integer()} | {:error, :unavailable}
  def backfill_batch(cursor_id, limit)
      when is_integer(cursor_id) and cursor_id >= 0 and is_integer(limit) and limit > 0 and
             limit <= 100 do
    case Repo.transaction(fn -> backfill_locked(cursor_id, limit) end) do
      {:ok, {next_cursor, count}} -> {:ok, next_cursor, count}
      {:error, _reason} -> {:error, :unavailable}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
    Ecto.ConstraintError -> {:error, :unavailable}
  end

  def backfill_batch(_cursor_id, _limit), do: {:error, :unavailable}

  defp backfill_locked(cursor_id, limit) do
    files =
      Repo.all(
        from(file in MediaFileSchema,
          join: library in LibrarySchema,
          on: library.id == file.library_id,
          where: library.content_type == :movie,
          where: file.id > ^cursor_id and file.availability == :available,
          order_by: file.id,
          limit: ^limit,
          lock: "FOR UPDATE"
        ),
        log: false
      )

    count =
      Enum.count(files, fn file ->
        case DecisionStore.lock(Repo, file.id) do
          nil -> insert_request!(Repo, file.id, file.revision)
          _existing -> false
        end
      end)

    next_cursor =
      case List.last(files) do
        nil -> cursor_id
        file -> file.id
      end

    {next_cursor, count}
  end

  defp request_one!(repo, file_id, revision) do
    eligible =
      repo.exists?(
        from(file in MediaFileSchema,
          join: library in LibrarySchema,
          on: library.id == file.library_id,
          where: file.id == ^file_id and library.content_type == :movie
        )
      )

    if eligible, do: request_video!(repo, file_id, revision), else: false
  end

  defp request_video!(repo, file_id, revision) do
    case DecisionStore.lock(repo, file_id) do
      nil -> insert_request!(repo, file_id, revision)
      %{origin: :manual} -> false
      existing -> update_request!(repo, existing, revision)
    end
  end

  defp insert_request!(repo, file_id, revision) do
    token = Ecto.UUID.generate()
    {:ok, requested} = Identification.new(file_id, revision, token)
    saved = DecisionStore.save!(repo, nil, requested)
    insert_job!(repo, saved)
    true
  end

  defp update_request!(repo, existing, revision) do
    token = Ecto.UUID.generate()
    decision = IdentificationMapper.to_domain(existing)
    {:ok, requested} = Identification.request(decision, revision, token)
    saved = DecisionStore.save!(repo, existing, requested)
    insert_job!(repo, saved)
    true
  end

  defp insert_job!(repo, decision) do
    {:ok, %{job: job}} =
      Ecto.Multi.new()
      |> Oban.insert(
        :job,
        IdentificationWorker.new(%{file_id: decision.media_file_id, token: decision.token}),
        log: false
      )
      |> repo.transaction()

    decision |> Ecto.Changeset.change(job_id: job.id) |> repo.update!(log: false)
  end
end
