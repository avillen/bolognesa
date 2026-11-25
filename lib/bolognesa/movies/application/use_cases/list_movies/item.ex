defmodule Bolognesa.Movies.Application.UseCases.ListMovies.Item do
  @moduledoc "Movie, physical version counts and the account's latest watched date in a catalog listing."
  alias Bolognesa.Movies.Application.Ports.Readers.MoviesReader
  alias Bolognesa.Movies.Domain.ReadModels.Movie
  alias Bolognesa.Movies.Domain.ReadModels.MovieVersion

  @type t :: %__MODULE__{
          id: Movie.id(),
          title: Movie.title(),
          year: Movie.year() | nil,
          poster_path: Movie.poster_path() | nil,
          version_count: MovieVersion.count(),
          available_count: MovieVersion.available_count(),
          last_watched_at: DateTime.t() | nil
        }

  defstruct [:id, :title, :year, :poster_path, :version_count, :available_count, :last_watched_at]

  @spec from_domain(MoviesReader.listed_movie()) :: t()
  def from_domain({%Movie{} = movie, version_count, available_count, last_watched_at}) do
    %__MODULE__{
      id: movie.id,
      title: movie.title,
      year: movie.year,
      poster_path: movie.poster_path,
      version_count: version_count,
      available_count: available_count,
      last_watched_at: last_watched_at
    }
  end
end
