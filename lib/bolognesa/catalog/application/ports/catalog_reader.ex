defmodule Bolognesa.Catalog.Application.Ports.CatalogReader do
  @moduledoc "Read domain records needed for catalog pages and movie details."

  alias Bolognesa.Catalog.Domain.Movie
  alias Bolognesa.Identification.Domain.Identification
  alias Bolognesa.Libraries.Domain.MediaFile

  @type adapter :: atom()
  @type listed_movie :: {Movie.t(), non_neg_integer(), non_neg_integer()}
  @type movie_version :: {MediaFile.t(), Identification.t()}

  @callback list_movies(binary(), pos_integer()) ::
              {:ok, {[listed_movie()], non_neg_integer()}} | {:error, :unavailable}

  @callback get_movie(pos_integer()) ::
              {:ok, {Movie.t(), [movie_version()]}} | {:error, :not_found | :unavailable}
end
