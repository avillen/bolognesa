defmodule Bolognesa.Movies.Infrastructure.Readers.EctoWatchedMoviesReader do
  @moduledoc false
  @behaviour Bolognesa.Movies.Application.Ports.Readers.WatchedMoviesReader
  import Ecto.Query
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.MovieIdentificationSchema
  alias Bolognesa.Infrastructure.Persistence.MovieSchema
  alias Bolognesa.Infrastructure.Persistence.MovieWatchedSchema
  alias Bolognesa.Movies.Infrastructure.Readers.EctoMoviesReader.MovieMapper
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
  def fetch_movie(movie_id) do
    if Repo.exists?(from(movie in MovieSchema, where: movie.id == ^movie_id), log: false),
      do: :ok,
      else: {:error, :not_found}
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  @impl true
  def list_recent_movies(user_id, library_id) do
    movies =
      from(watched in MovieWatchedSchema,
        join: movie in MovieSchema,
        on: movie.id == watched.movie_id,
        where: watched.user_id == ^user_id,
        order_by: [desc: watched.last_watched_at, asc: movie.id],
        limit: 3,
        select: movie
      )
      |> in_library(library_id)
      |> Repo.all(log: false)

    {:ok, Enum.map(movies, &MovieMapper.to_movie/1)}
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp in_library(query, nil), do: query

  defp in_library(query, library_id) do
    ids =
      from identification in MovieIdentificationSchema,
        join: file in MediaFileSchema,
        on: file.id == identification.media_file_id,
        where: file.library_id == ^library_id and identification.state in [:automatic, :manual],
        select: identification.movie_id

    where(query, [_watched, movie], movie.id in subquery(ids))
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
