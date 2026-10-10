defmodule Bolognesa.Catalog.Application.Ports.CatalogReader do
  @moduledoc "Read domain records needed for catalog pages and movie details."

  alias Bolognesa.Catalog.Domain.{Movie, MovieVersion}

  @type adapter :: atom()
  @type listed_movie :: {Movie.t(), non_neg_integer(), non_neg_integer()}

  @callback list_movies(binary(), pos_integer()) ::
              {:ok, {[listed_movie()], non_neg_integer()}} | {:error, :unavailable}

  @callback get_movie(pos_integer()) ::
              {:ok, {Movie.t(), [MovieVersion.t()]}} | {:error, :not_found | :unavailable}
end
