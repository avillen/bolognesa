defmodule Bolognesa.Libraries.Infrastructure.Repositories.EctoInspectionRepository.InspectionRequestWriter do
  alias Ecto.UUID
  @moduledoc "Persist an inspection and its durable job inside the caller's transaction."
  alias Bolognesa.Infrastructure.Persistence.InspectionSchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Libraries.Infrastructure.Jobs.Oban.ObanInspectionJob
  alias Bolognesa.Repo

  @spec enqueue!(MediaFileSchema.t(), InspectionSchema.t() | nil) :: InspectionSchema.t()
  def enqueue!(file, current) do
    token = UUID.generate()

    attrs = %{
      media_file_id: file.id,
      token: token,
      observed_revision: file.revision,
      state: :pending,
      failure_reason: nil,
      job_id: nil,
      format: nil,
      duration_ms: nil,
      tracks: %{"items" => []},
      music_tags: nil,
      started_at: nil,
      finished_at: nil
    }

    inspection =
      case current do
        nil -> Repo.insert!(InspectionSchema.changeset(%InspectionSchema{}, attrs))
        schema -> Repo.update!(InspectionSchema.changeset(schema, attrs))
      end

    job = ObanInspectionJob.insert!(file.id, token)

    inspection |> InspectionSchema.changeset(%{job_id: job.id}) |> Repo.update!()
  end
end
