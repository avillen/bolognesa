defmodule Bolognesa.Catalog.Application.Dto.MoviePage do
  @moduledoc "A page of catalog movie listing results."

  alias Bolognesa.Catalog.Application.Dto.MovieListItem
  alias Bolognesa.Catalog.Domain.Movie

  @enforce_keys [:items, :total]
  defstruct [:items, :total]

  @type t :: %__MODULE__{items: [MovieListItem.t()], total: Movie.count()}
end
