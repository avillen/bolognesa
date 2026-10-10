defmodule Bolognesa.Identification.Application.Dto.ReviewItem do
  @moduledoc "Identification and file details shown in the review list."

  alias Bolognesa.Identification.Domain.Identification
  alias Bolognesa.Libraries.Domain.MediaFile

  @enforce_keys [
    :file_id,
    :state,
    :needs_review,
    :failure_reason,
    :availability,
    :filename,
    :movie_id,
    :movie_title,
    :candidates
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          file_id: MediaFile.id(),
          state: Identification.state(),
          needs_review: boolean(),
          failure_reason: binary() | nil,
          availability: MediaFile.availability(),
          filename: String.t(),
          movie_id: pos_integer() | nil,
          movie_title: String.t() | nil,
          candidates: Identification.candidate_data()
        }
end
