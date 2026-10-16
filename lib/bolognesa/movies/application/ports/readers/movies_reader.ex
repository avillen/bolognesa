defmodule Bolognesa.Movies.Application.Ports.Readers.MoviesReader do
  @moduledoc "Read domain records needed for catalog pages and movie details."
  alias Bolognesa.Movies.Domain.ReadModels.Movie
  alias Bolognesa.Movies.Domain.ReadModels.MovieVersion

  @type adapter :: atom()
  @type library_id :: pos_integer() | nil

  @typedoc "One-based page number for a catalog listing."
  @type page_number :: pos_integer()

  @typedoc "Movie, total associated versions, and available associated versions, in that order."
  @type listed_movie :: {Movie.t(), MovieVersion.count(), MovieVersion.available_count()}

  @callback list_movies(query :: String.t(), page :: page_number(), library_id :: library_id()) ::
              {:ok, {[listed_movie()], Movie.count()}} | {:error, :unavailable}

  @callback get_movie(Movie.id()) ::
              {:ok, {Movie.t(), [MovieVersion.t()]}} | {:error, :not_found | :unavailable}
end
