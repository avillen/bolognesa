defmodule Bolognesa.Infrastructure.Jobs.IdentificationRecovery do
  @moduledoc false
  import Ecto.Query
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Oban.Job

  @spec interrupted(atom(), DateTime.t(), module(), :movie | :series) ::
          [{pos_integer(), String.t(), String.t() | nil}]
  def interrupted(repo, now, schema, content_type) do
    cutoff = DateTime.add(now, -60, :second)

    repo.all(
      from(identification in schema,
        join: file in MediaFileSchema,
        on: file.id == identification.media_file_id,
        join: library in LibrarySchema,
        on: library.id == file.library_id,
        where: library.content_type == ^content_type,
        left_join: job in Job,
        on: job.id == identification.job_id,
        where: identification.state == :pending and not is_nil(identification.job_id),
        where:
          is_nil(job.id) or job.state in ["discarded", "cancelled", "completed"] or
            (job.state == "executing" and job.attempted_at < ^cutoff and
               identification.started_at < ^cutoff),
        order_by: identification.id,
        limit: 100,
        select: {identification.media_file_id, identification.token, job.state}
      ),
      log: false
    )
  end
end
