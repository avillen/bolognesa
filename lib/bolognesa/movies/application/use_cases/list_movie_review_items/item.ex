defmodule Bolognesa.Movies.Application.UseCases.ListMovieReviewItems.Item do
  @moduledoc "Identification and file details shown in the review list."

  alias Bolognesa.Movies.Domain.Entities.Identification
  alias Bolognesa.Movies.Domain.ReadModels.ReviewMovie
  alias Bolognesa.Movies.Domain.ReadModels.ReviewMovieFile

  @type t :: %__MODULE__{
          file_id: pos_integer(),
          state: Identification.state(),
          failure_reason: binary() | nil,
          availability: ReviewMovieFile.availability(),
          filename: String.t(),
          movie_title: String.t() | nil
        }

  defstruct [
    :file_id,
    :state,
    :failure_reason,
    :availability,
    :filename,
    :movie_title
  ]

  @spec from_domain({Identification.t(), ReviewMovieFile.t(), ReviewMovie.t() | nil}) :: t()
  def from_domain({%Identification{} = decision, %ReviewMovieFile{} = file, movie}) do
    %__MODULE__{
      file_id: file.id,
      state: decision.state,
      failure_reason: decision.failure_reason,
      availability: file.availability,
      filename: safe_basename(file.relative_path),
      movie_title: movie_title(movie)
    }
  end

  defp movie_title(nil), do: nil
  defp movie_title(%ReviewMovie{title: title}), do: title

  defp safe_basename(path) when is_binary(path) do
    name = :filename.basename(path)
    if String.valid?(name), do: name, else: "Archivo"
  end
end
