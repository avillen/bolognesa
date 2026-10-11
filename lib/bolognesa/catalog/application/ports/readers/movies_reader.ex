defmodule Bolognesa.Catalog.Application.Ports.Readers.MoviesReader do
  @moduledoc "Read domain records needed for catalog pages and movie details."
  alias Bolognesa.Catalog.Domain.ReadModels.Movies.Movie
  alias Bolognesa.Catalog.Domain.ReadModels.Movies.MovieVersion

  @type adapter :: atom()

  @typedoc "One-based page number for a catalog listing."
  @type page_number :: pos_integer()

  @typedoc "Movie, total associated versions, and available associated versions, in that order."
  @type listed_movie :: {Movie.t(), MovieVersion.count(), MovieVersion.available_count()}

  @callback list_movies(query :: String.t(), page :: page_number()) ::
              {:ok, {[listed_movie()], Movie.count()}} | {:error, :unavailable}

  @callback get_movie(movie_id :: Movie.id()) ::
              {:ok, {Movie.t(), [MovieVersion.t()]}} | {:error, :not_found | :unavailable}
end
