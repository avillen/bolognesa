defmodule Bolognesa.Catalog.Application.Dto.MovieListItem do
  @moduledoc "Movie and physical version counts in a catalog listing."
  alias Bolognesa.Catalog.Domain.ReadModels.Movies.Movie
  alias Bolognesa.Catalog.Domain.ReadModels.Movies.MovieVersion

  @type t :: %__MODULE__{
          id: Movie.id(),
          title: Movie.title(),
          year: Movie.year() | nil,
          poster_path: Movie.poster_path() | nil,
          version_count: MovieVersion.count(),
          available_count: MovieVersion.available_count()
        }

  defstruct [:id, :title, :year, :poster_path, :version_count, :available_count]

  @spec from_domain({Movie.t(), MovieVersion.count(), MovieVersion.available_count()}) :: t()
  def from_domain({%Movie{} = movie, version_count, available_count}) do
    %__MODULE__{
      id: movie.id,
      title: movie.title,
      year: movie.year,
      poster_path: movie.poster_path,
      version_count: version_count,
      available_count: available_count
    }
  end
end
