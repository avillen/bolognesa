defmodule Bolognesa.Music.Infrastructure.Jobs.Oban.ObanImportJob do
  @moduledoc "Inserts a music import job using the caller's transaction repository."

  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Music.Infrastructure.Jobs.Workers.RefreshWorker

  @spec insert!(Bolognesa.Music.transaction_repository(), MediaFileSchema.t()) :: Oban.Job.t()
  def insert!(repo, file) do
    {:ok, %{job: job}} =
      Ecto.Multi.new()
      |> Oban.insert(:job, RefreshWorker.new(%{file_id: file.id, revision: file.revision}))
      |> repo.transaction()

    job
  end
end
