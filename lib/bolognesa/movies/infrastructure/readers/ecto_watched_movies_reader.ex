defmodule Bolognesa.Movies.Infrastructure.Readers.EctoWatchedMoviesReader do
  @moduledoc false
  @behaviour Bolognesa.Movies.Application.Ports.Readers.WatchedMoviesReader
  import Ecto.Query
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.MovieIdentificationSchema
  alias Bolognesa.Infrastructure.Persistence.MovieWatchedSchema
  alias Bolognesa.Repo

  @impl true
  def fetch_last_watched_at(user_id, movie_id) do
    {:ok,
     Repo.one(
       from(watched in MovieWatchedSchema,
         where: watched.user_id == ^user_id and watched.movie_id == ^movie_id,
         select: watched.last_watched_at
       ),
       log: false
     )}
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  @impl true
  def fetch_played_movie(movie_id, file_id) do
    played? =
      Repo.exists?(
        from(file in MediaFileSchema,
          join: identification in MovieIdentificationSchema,
          on: identification.media_file_id == file.id,
          where:
            file.id == ^file_id and file.availability == :available and
              identification.movie_id == ^movie_id and
              identification.state in [:automatic, :manual]
        ),
        log: false
      )

    if played?, do: :ok, else: {:error, :not_found}
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end
end
