defmodule Bolognesa.Music.Infrastructure.Repositories.EctoImportRepository.ObanJobRecovery do
  @moduledoc "Finds interrupted music imports and interprets their job state."
  import Ecto.Query

  alias Bolognesa.Infrastructure.Persistence.{
    InspectionSchema,
    LibrarySchema,
    MediaFileSchema,
    MusicImportSchema
  }

  alias Bolognesa.Repo

  @spec list_interrupted(DateTime.t()) :: [pos_integer()]
  def list_interrupted(cutoff) do
    Repo.all(
      from(row in MusicImportSchema,
        join: file in MediaFileSchema,
        on: file.id == row.media_file_id,
        join: library in LibrarySchema,
        on: library.id == file.library_id,
        join: inspection in InspectionSchema,
        on: inspection.media_file_id == file.id,
        where: file.availability == :available,
        where: library.content_type == :music,
        where: inspection.state == :succeeded,
        where: inspection.observed_revision == file.revision,
        where: row.observed_revision == file.revision,
        where: row.inspection_token == inspection.token,
        where: fragment(~s|? @> '{"items":[{"kind":"audio"}]}'::jsonb|, inspection.tracks),
        left_join: job in Oban.Job,
        on: job.id == row.job_id,
        where: row.state in [:pending, :running],
        where:
          is_nil(job.id) or job.state in ["discarded", "cancelled", "completed"] or
            (row.state == :running and job.state in ["retryable", "available"]) or
            (row.state == :running and row.started_at < ^cutoff and job.state == "executing" and
               job.attempted_at < ^cutoff),
        order_by: row.id,
        limit: 100,
        select: row.media_file_id
      )
    )
  end

  @spec get_job(pos_integer() | nil) :: Oban.Job.t() | nil
  def get_job(nil), do: nil
  def get_job(id), do: Repo.get(Oban.Job, id)

  @spec failure_reason(Oban.Job.t() | nil, DateTime.t()) ::
          :unexpected_failure | :attempts_exhausted | nil
  def failure_reason(nil, _cutoff), do: :unexpected_failure
  def failure_reason(%{state: "discarded"}, _cutoff), do: :attempts_exhausted

  def failure_reason(%{state: state}, _cutoff) when state in ["cancelled", "completed"],
    do: :unexpected_failure

  def failure_reason(%{state: "executing", attempted_at: attempted}, cutoff)
      when not is_nil(attempted) do
    if DateTime.compare(attempted, cutoff) == :lt, do: :unexpected_failure, else: nil
  end

  def failure_reason(_job, _cutoff), do: nil
end
