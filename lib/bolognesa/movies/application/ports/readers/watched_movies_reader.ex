defmodule Bolognesa.Movies.Application.Ports.Readers.WatchedMoviesReader do
  @moduledoc "The account's watched state of movies, and validation of the current played file."
  alias Bolognesa.Movies.Domain.ReadModels.Movie

  @type adapter :: module()

  @doc "The account's latest watched date for the movie, or nil when unwatched."
  @callback fetch_last_watched_at(user_id :: pos_integer(), Movie.id()) ::
              {:ok, DateTime.t() | nil} | {:error, :unavailable}

  @doc "Confirm that the catalog movie exists."
  @callback fetch_movie(Movie.id()) :: :ok | {:error, :not_found | :unavailable}

  @doc "List up to three movies the account watched most recently, newest first; optionally only movies with a confirmed file in the library."
  @callback list_recent_movies(user_id :: pos_integer(), library_id :: pos_integer() | nil) ::
              {:ok, [Movie.t()]} | {:error, :unavailable}

  @doc "Confirm that the file is available and identified with the movie."
  @callback fetch_played_movie(Movie.id(), file_id :: pos_integer()) ::
              :ok | {:error, :not_found | :unavailable}
end
