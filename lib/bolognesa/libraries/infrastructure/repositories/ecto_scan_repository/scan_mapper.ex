defmodule Bolognesa.Libraries.Infrastructure.Repositories.EctoScanRepository.ScanMapper do
  @moduledoc false
  alias Bolognesa.Infrastructure.Persistence.ScanSchema
  alias Bolognesa.Libraries.Domain.Entities.Scan

  @spec to_scan(ScanSchema.t()) :: Scan.t()
  def to_scan(%ScanSchema{job_id: job_id} = schema) when is_integer(job_id) do
    %Scan{
      id: schema.id,
      library_id: schema.library_id,
      job_id: schema.job_id,
      state: schema.state,
      force_inspection?: schema.force_inspection,
      generation: schema.generation,
      attempt: schema.attempt,
      files_discovered: schema.files_discovered,
      failure_reason: schema.failure_reason,
      requested_at: schema.requested_at,
      started_at: schema.started_at,
      attempt_started_at: schema.attempt_started_at,
      finished_at: schema.finished_at,
      updated_at: schema.updated_at
    }
  end
end
