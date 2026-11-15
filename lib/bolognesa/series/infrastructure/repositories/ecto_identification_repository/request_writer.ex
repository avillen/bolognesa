defmodule Bolognesa.Series.Infrastructure.Repositories.EctoIdentificationRepository.RequestWriter do
  alias Ecto.Changeset
  alias Ecto.Multi
  alias Ecto.UUID
  @moduledoc "Writes identification requests in the inventory transaction."

  import Ecto.Query

  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Series.Domain.Entities.Identification
  alias Bolognesa.Series.Infrastructure.Jobs.Oban.ObanIdentificationJob
  alias Bolognesa.Series.Infrastructure.Repositories.EctoIdentificationRepository.DecisionStore
  alias Bolognesa.Series.Infrastructure.Repositories.EctoIdentificationRepository.EntryStore
  alias Bolognesa.Series.Infrastructure.Repositories.IdentificationMapper

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

  defp request_one!(repo, file_id, revision) do
    eligible =
      repo.exists?(
        from(file in MediaFileSchema,
          join: library in LibrarySchema,
          on: library.id == file.library_id,
          where: file.id == ^file_id and library.content_type == :series
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
    token = UUID.generate()
    {:ok, requested} = Identification.new(file_id, revision, token)
    saved = DecisionStore.save!(repo, nil, requested)
    insert_job!(repo, saved)
    true
  end

  defp update_request!(repo, existing, revision) do
    token = UUID.generate()
    decision = IdentificationMapper.to_domain(existing, EntryStore.ids(repo, existing.id))
    {:ok, requested} = Identification.request(decision, revision, token)
    saved = DecisionStore.save!(repo, existing, requested)
    EntryStore.replace!(repo, saved.id, requested.episode_ids)
    insert_job!(repo, saved)
    true
  end

  defp insert_job!(repo, decision) do
    {:ok, %{job: job}} =
      Multi.new()
      |> ObanIdentificationJob.insert(decision)
      |> repo.transaction()

    decision |> Changeset.change(job_id: job.id) |> repo.update!(log: false)
  end
end
