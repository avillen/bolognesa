defmodule Bolognesa.Catalog.Application.Dto.MovieDetail do
  @moduledoc "Movie detail returned by the catalog read use case."

  alias Bolognesa.Catalog.Application.Dto.MovieVersion
  alias Bolognesa.Catalog.Domain.Movie

  @enforce_keys [:movie, :versions]
  defstruct [:movie, :versions]

  @type t :: %__MODULE__{movie: Movie.t(), versions: [MovieVersion.t()]}
end
