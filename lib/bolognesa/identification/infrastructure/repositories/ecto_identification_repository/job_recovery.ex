defmodule Bolognesa.Identification.Infrastructure.Repositories.EctoIdentificationRepository.JobRecovery do
  @moduledoc false
  import Ecto.Query

  alias Bolognesa.Identification.Domain.Identification

  alias Bolognesa.Identification.Infrastructure.Repositories.EctoIdentificationRepository.DecisionStore

  alias Bolognesa.Infrastructure.Persistence.IdentificationSchema
  alias Oban.Job

  @spec interrupted(DecisionStore.repo(), DateTime.t()) ::
          [{pos_integer(), Identification.token(), binary() | nil}]
  def interrupted(repo, now) do
    cutoff = DateTime.add(now, -60, :second)

    repo.all(
      from(identification in IdentificationSchema,
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
