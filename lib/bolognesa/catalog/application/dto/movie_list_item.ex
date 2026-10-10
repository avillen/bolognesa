defmodule Bolognesa.Catalog.Application.Dto.MovieListItem do
  @moduledoc "Movie and physical version counts in a catalog listing."

  alias Bolognesa.Catalog.Domain.Movie

  @enforce_keys [:id, :title, :year, :poster_path, :version_count, :available_count]
  defstruct [:id, :title, :year, :poster_path, :version_count, :available_count]

  @type t :: %__MODULE__{
          id: Movie.id(),
          title: Movie.title(),
          year: Movie.year() | nil,
          poster_path: Movie.poster_path() | nil,
          version_count: non_neg_integer(),
          available_count: non_neg_integer()
        }
end
