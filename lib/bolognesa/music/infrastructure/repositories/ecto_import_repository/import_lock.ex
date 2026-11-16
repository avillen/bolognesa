defmodule Bolognesa.Music.Infrastructure.Repositories.EctoImportRepository.ImportLock do
  @moduledoc false
  import Ecto.Query

  alias Bolognesa.Infrastructure.Persistence.InspectionSchema
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.MusicImportSchema
  alias Bolognesa.Repo

  @type result ::
          {:ok, MediaFileSchema.t(), InspectionSchema.t(), %MusicImportSchema{} | nil} | :stale

  @doc "Locks inventory, inspection, then import state (decision 0018) and checks eligibility."
  @spec lock(pos_integer(), Bolognesa.Music.transaction_repository()) :: result()
  def lock(file_id, repo \\ Repo) do
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
        from(row in MusicImportSchema, where: row.media_file_id == ^file_id, lock: "FOR UPDATE"),
        log: false
      )

    if eligible?(file, inspection, repo), do: {:ok, file, inspection, state}, else: :stale
  end

  defp eligible?(nil, _inspection, _repo), do: false
  defp eligible?(_file, nil, _repo), do: false

  defp eligible?(file, inspection, repo) do
    file.availability == :available &&
      repo.get!(LibrarySchema, file.library_id, log: false).content_type == :music &&
      inspection.state == :succeeded && inspection.observed_revision == file.revision &&
      Enum.any?(inspection.tracks["items"] || [], &(&1["kind"] == "audio"))
  end
end
