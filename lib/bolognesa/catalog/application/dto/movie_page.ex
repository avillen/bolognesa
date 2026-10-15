defmodule Bolognesa.Catalog.Application.Dto.MoviePage do
  @moduledoc "A page of catalog movie listing results."

  alias Bolognesa.Catalog.Application.Dto.MovieListItem
  alias Bolognesa.Catalog.Domain.ReadModels.Movies.Movie
  alias Bolognesa.Catalog.Domain.ReadModels.Movies.MovieVersion

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
