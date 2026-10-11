defmodule Bolognesa.Identification.Infrastructure.Persistence.IdentificationMapper do
  @moduledoc false
  alias Bolognesa.Identification.Domain.Identification

  @spec to_domain(map()) :: Identification.t()
  def to_domain(row) do
    %Identification{
      media_file_id: row.media_file_id,
      catalog_entry_id: row.catalog_entry_id,
      state: row.state,
      origin: row.origin,
      observed_revision: row.observed_revision,
      token: row.token,
      needs_review?: row.needs_review,
      failure_reason: row.failure_reason,
      candidate_data: row.candidate_data,
      job_id: row.job_id,
      started_at: row.started_at,
      finished_at: row.finished_at
    }
  end
end
