defmodule Bolognesa.Movies.Application.UseCases.GetMovie.Response do
  @moduledoc "Movie detail returned by the catalog read use case, with the account's latest watched date, if any."

  alias Bolognesa.Movies.Application.UseCases.GetMovie.Version, as: MovieVersionDto
  alias Bolognesa.Movies.Domain.ReadModels.Movie
  alias Bolognesa.Movies.Domain.ReadModels.MovieVersion

  @type t :: %__MODULE__{
          movie: Movie.t(),
          versions: [MovieVersionDto.t()],
          last_watched_at: DateTime.t() | nil
        }

  defstruct [:movie, :versions, :last_watched_at]

  @spec from_domain({Movie.t(), [MovieVersion.t()]}, DateTime.t() | nil) :: t()
  def from_domain({movie, versions}, last_watched_at),
    do: %__MODULE__{
      movie: movie,
      versions: Enum.map(versions, &MovieVersionDto.from_domain/1),
      last_watched_at: last_watched_at
    }
end
