defmodule Bolognesa.Catalog.Application.Dto.MoviePage do
  @moduledoc "A page of catalog movie listing results."

  alias Bolognesa.Catalog.Application.Dto.MovieListItem
  alias Bolognesa.Catalog.Domain.{Movie, MovieVersion}

  @enforce_keys [:items, :total]
  defstruct [:items, :total]

  @type t :: %__MODULE__{items: [MovieListItem.t()], total: Movie.count()}

  @spec from_domain(
          {[{Movie.t(), MovieVersion.count(), MovieVersion.available_count()}], Movie.count()}
        ) ::
          t()
  def from_domain({rows, total}),
    do: %__MODULE__{items: Enum.map(rows, &MovieListItem.from_domain/1), total: total}
end
