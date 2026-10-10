defmodule Bolognesa.Catalog.Application.Dto.MoviePage do
  @moduledoc "A page of catalog movie listing results."

  alias Bolognesa.Catalog.Application.Dto.MovieListItem

  @enforce_keys [:items, :total]
  defstruct [:items, :total]

  @type t :: %__MODULE__{items: [MovieListItem.t()], total: non_neg_integer()}
end
