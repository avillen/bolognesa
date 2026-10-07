defmodule Bolognesa.Identification.Infrastructure.Persistence.EctoRequestWriter do
  @moduledoc "Writes identification requests in the inventory transaction."

  import Ecto.Query

  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository.{
    EventSchema,
    IdentificationSchema
  }

  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository.MediaFileSchema
  alias Bolognesa.Repo

  @type request_entry :: %{
          required(:file_id) => pos_integer(),
          required(:revision) => pos_integer(),
          required(:requested?) => boolean()
        }

  @spec request_batch!(module(), [request_entry()]) :: non_neg_integer()
  def request_batch!(repo, entries) do
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
          where: file.id > ^cursor_id and file.availability == :available,
          order_by: file.id,
          limit: ^limit,
          lock: "FOR UPDATE"
        ),
        log: false
      )

    count =
      Enum.count(files, fn file ->
        case locked_identification(Repo, file.id) do
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
    case locked_identification(repo, file_id) do
      nil -> insert_request!(repo, file_id, revision)
      %{origin: :manual} -> false
      existing -> update_request!(repo, existing, revision)
    end
  end

  defp locked_identification(repo, file_id) do
    repo.one(
      from(identification in IdentificationSchema,
        where: identification.media_file_id == ^file_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp insert_request!(repo, file_id, revision) do
    token = Ecto.UUID.generate()

    repo.insert!(
      IdentificationSchema.changeset(%IdentificationSchema{}, %{
        media_file_id: file_id,
        observed_revision: revision,
        token: token,
        state: :pending
      })
    )

    insert_event!(repo, file_id, token)
    true
  end

  defp update_request!(repo, existing, revision) do
    token = Ecto.UUID.generate()

    repo.update!(
      IdentificationSchema.changeset(existing, %{
        observed_revision: revision,
        token: token,
        state: :pending,
        needs_review: false,
        failure_reason: nil,
        job_id: nil,
        started_at: nil,
        finished_at: nil
      })
    )

    insert_event!(repo, existing.media_file_id, token)
    true
  end

  defp insert_event!(repo, file_id, token) do
    repo.insert!(EventSchema.changeset(%EventSchema{}, %{media_file_id: file_id, token: token}))
  end
end
