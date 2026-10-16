defmodule Bolognesa.Movies.Infrastructure.Repositories.IdentificationMapper do
  @moduledoc false
  alias Bolognesa.Infrastructure.Persistence.MovieIdentificationSchema
  alias Bolognesa.Movies.Domain.Entities.Identification

  @type attributes :: %{
          media_file_id: pos_integer(),
          movie_id: pos_integer() | nil,
          state: Identification.state(),
          origin: Identification.origin(),
          observed_revision: pos_integer(),
          token: Identification.token(),
          needs_review: boolean(),
          failure_reason: binary() | nil,
          candidate_data: Identification.candidate_data(),
          job_id: pos_integer() | nil,
          started_at: DateTime.t() | nil,
          finished_at: DateTime.t() | nil
        }

  @spec to_domain(MovieIdentificationSchema.t()) :: Identification.t()
  def to_domain(row) do
    %Identification{
      media_file_id: row.media_file_id,
      movie_id: row.movie_id,
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

  @spec to_attributes(Identification.t()) :: attributes()
  def to_attributes(decision) do
    %{
      media_file_id: decision.media_file_id,
      movie_id: decision.movie_id,
      state: decision.state,
      origin: decision.origin,
      observed_revision: decision.observed_revision,
      token: decision.token,
      needs_review: decision.needs_review?,
      failure_reason: decision.failure_reason,
      candidate_data: decision.candidate_data,
      job_id: decision.job_id,
      started_at: decision.started_at,
      finished_at: decision.finished_at
    }
  end
end
