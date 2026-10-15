defmodule Bolognesa.Catalog.Application.Dto.MovieDetail do
  @moduledoc "Movie detail returned by the catalog read use case."

  alias Bolognesa.Catalog.Application.Dto.MovieVersion, as: MovieVersionDto
  alias Bolognesa.Catalog.Domain.ReadModels.Movies.Movie
  alias Bolognesa.Catalog.Domain.ReadModels.Movies.MovieVersion

  @type t :: %__MODULE__{
          movie: Movie.t(),
          versions: [MovieVersionDto.t()]
        }

  defstruct [:movie, :versions]

  @spec from_domain({Movie.t(), [MovieVersion.t()]}) :: t()
  def from_domain({movie, versions}),
    do: %__MODULE__{movie: movie, versions: Enum.map(versions, &MovieVersionDto.from_domain/1)}
end
