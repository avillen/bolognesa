defmodule Bolognesa.Movies.Application.Ports.Readers.WatchedMoviesReader do
  @moduledoc "The account's watched state of a movie, and validation of the current played file."
  alias Bolognesa.Movies.Domain.ReadModels.Movie

  @type adapter :: module()

  @doc "The account's latest watched date for the movie, or nil when unwatched."
  @callback fetch_last_watched_at(user_id :: pos_integer(), Movie.id()) ::
              {:ok, DateTime.t() | nil} | {:error, :unavailable}

  @doc "Confirm that the catalog movie exists."
  @callback fetch_movie(Movie.id()) :: :ok | {:error, :not_found | :unavailable}

  @doc "Confirm that the file is available and identified with the movie."
  @callback fetch_played_movie(Movie.id(), file_id :: pos_integer()) ::
              :ok | {:error, :not_found | :unavailable}
end
