defmodule Bolognesa.Movies.Application.UseCases.ListMovieReviewItems.Item do
  @moduledoc "Identification and file details shown in the review list."

  alias Bolognesa.Movies.Domain.Entities.Identification
  alias Bolognesa.Movies.Domain.ReadModels.ReviewMovie
  alias Bolognesa.Movies.Domain.ReadModels.ReviewMovieFile

  @type t :: %__MODULE__{
          file_id: pos_integer(),
          state: Identification.state(),
          needs_review: boolean(),
          failure_reason: binary() | nil,
          availability: ReviewMovieFile.availability(),
          filename: String.t(),
          movie_id: pos_integer() | nil,
          movie_title: String.t() | nil,
          candidates: Identification.candidate_data()
        }

  defstruct [
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

  @spec from_domain({Identification.t(), ReviewMovieFile.t(), ReviewMovie.t() | nil}) :: t()
  def from_domain({%Identification{} = decision, %ReviewMovieFile{} = file, movie}) do
    {movie_id, movie_title} = movie_details(movie)

    %__MODULE__{
      file_id: file.id,
      state: decision.state,
      needs_review: decision.needs_review?,
      failure_reason: decision.failure_reason,
      availability: file.availability,
      filename: safe_basename(file.relative_path),
      movie_id: movie_id,
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
