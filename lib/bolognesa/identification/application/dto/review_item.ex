defmodule Bolognesa.Identification.Application.Dto.ReviewItem do
  @moduledoc "Identification and file details shown in the review list."

  alias Bolognesa.Identification.Domain.Identification
  alias Bolognesa.Identification.Domain.ReviewFile
  alias Bolognesa.Identification.Domain.ReviewMovie

  @enforce_keys [
    :file_id,
    :state,
    :needs_review,
    :failure_reason,
    :availability,
    :filename,
    :catalog_entry_id,
    :movie_title,
    :candidates
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          file_id: pos_integer(),
          state: Identification.state(),
          needs_review: boolean(),
          failure_reason: binary() | nil,
          availability: ReviewFile.availability(),
          filename: String.t(),
          catalog_entry_id: pos_integer() | nil,
          movie_title: String.t() | nil,
          candidates: Identification.candidate_data()
        }

  @spec from_domain({Identification.t(), ReviewFile.t(), ReviewMovie.t() | nil}) :: t()
  def from_domain({%Identification{} = decision, %ReviewFile{} = file, movie}) do
    {catalog_entry_id, movie_title} = movie_details(movie)

    %__MODULE__{
      file_id: file.id,
      state: decision.state,
      needs_review: decision.needs_review?,
      failure_reason: decision.failure_reason,
      availability: file.availability,
      filename: safe_basename(file.relative_path),
      catalog_entry_id: catalog_entry_id,
      movie_title: movie_title,
      candidates: decision.candidate_data
    }
  end

  defp movie_details(nil), do: {nil, nil}
  defp movie_details(%ReviewMovie{id: id, title: title}), do: {id, title}

  defp safe_basename(path) when is_binary(path) do
    name = :filename.basename(path)
    if String.valid?(name), do: name, else: "Archivo"
  end
end
