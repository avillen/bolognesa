defmodule Bolognesa.Movies.Infrastructure.Repositories.EctoWatchedMoviesRepository do
  @moduledoc false
  @behaviour Bolognesa.Movies.Application.Ports.Repositories.WatchedMoviesRepository
  import Ecto.Query
  alias Bolognesa.Infrastructure.Persistence.MovieWatchedSchema
  alias Bolognesa.Repo

  @impl true
  def upsert(user_id, movie_id, watched_at) do
    on_conflict =
      from watched in MovieWatchedSchema,
        update: [
          set: [
            last_watched_at:
              fragment("GREATEST(?, EXCLUDED.last_watched_at)", watched.last_watched_at)
          ]
        ]

    Repo.insert_all(
      MovieWatchedSchema,
      [%{user_id: user_id, movie_id: movie_id, last_watched_at: watched_at}],
      on_conflict: on_conflict,
      conflict_target: [:user_id, :movie_id],
      log: false
    )

    :ok
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end
end
