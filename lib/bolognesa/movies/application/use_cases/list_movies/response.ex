defmodule Bolognesa.Movies.Application.UseCases.ListMovies.Response do
  @moduledoc "A page of catalog movie listing results."

  alias Bolognesa.Movies.Application.UseCases.ListMovies.Item, as: MovieListItem
  alias Bolognesa.Movies.Domain.ReadModels.Movie
  alias Bolognesa.Movies.Domain.ReadModels.MovieVersion

  @type t :: %__MODULE__{
          items: [MovieListItem.t()],
          total: Movie.count()
        }

  defstruct [:items, :total]

  @spec from_domain(
          {[{Movie.t(), MovieVersion.count(), MovieVersion.available_count()}], Movie.count()}
        ) ::
          t()
  def from_domain({rows, total}),
    do: %__MODULE__{items: Enum.map(rows, &MovieListItem.from_domain/1), total: total}
end
