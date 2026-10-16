defmodule Bolognesa.Movies.Application.UseCases.GetMovie.Response do
  @moduledoc "Movie detail returned by the catalog read use case."

  alias Bolognesa.Movies.Application.UseCases.GetMovie.Version, as: MovieVersionDto
  alias Bolognesa.Movies.Domain.ReadModels.Movie
  alias Bolognesa.Movies.Domain.ReadModels.MovieVersion

  @type t :: %__MODULE__{
          movie: Movie.t(),
          versions: [MovieVersionDto.t()]
        }

  defstruct [:movie, :versions]

  @spec from_domain({Movie.t(), [MovieVersion.t()]}) :: t()
  def from_domain({movie, versions}),
    do: %__MODULE__{movie: movie, versions: Enum.map(versions, &MovieVersionDto.from_domain/1)}
end
