defmodule Bolognesa.Movies.Infrastructure.Readers.EctoMoviesReader do
  @moduledoc false
  @behaviour Bolognesa.Movies.Application.Ports.Readers.MoviesReader

  import Ecto.Query

  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.MovieIdentificationSchema
  alias Bolognesa.Infrastructure.Persistence.MovieSchema
  alias Bolognesa.Movies.Domain.ReadModels.MovieVersion
  alias Bolognesa.Movies.Infrastructure.Readers.EctoMoviesReader.MovieMapper
  alias Bolognesa.Repo

  @page_size 24
  @max_versions 100

  @impl true
  def list_movies(query, page, library_id) do
    filtered =
      from movie in MovieSchema,
        where: fragment("strpos(lower(?), lower(?)) > 0", movie.title, ^query)

    filtered = restrict_library(filtered, library_id)

    total = Repo.aggregate(filtered, :count, :id, log: false)
    offset = (page - 1) * @page_size

    rows =
      Repo.all(
        from(movie in filtered,
          left_join: identification in MovieIdentificationSchema,
          on:
            identification.movie_id == movie.id and
              identification.state in [:automatic, :manual],
          left_join: file in MediaFileSchema,
          as: :file,
          on: file.id == identification.media_file_id,
          group_by: movie.id,
          order_by: [asc: movie.title, asc: movie.id],
          limit: @page_size,
          offset: ^offset,
          select: {movie, count(file.id), filter(count(file.id), file.availability == :available)}
        )
        |> restrict_files(library_id),
        log: false
      )

    entries =
      Enum.map(rows, fn {movie, version_count, available_count} ->
        {MovieMapper.to_movie(movie), version_count, available_count}
      end)

    {:ok, {entries, total}}
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp restrict_library(query, nil), do: query

  defp restrict_library(query, library_id) do
    ids =
      from decision in MovieIdentificationSchema,
        join: file in MediaFileSchema,
        on: file.id == decision.media_file_id,
        where: file.library_id == ^library_id and decision.state in [:automatic, :manual],
        select: decision.movie_id

    from entry in query, where: entry.id in subquery(ids)
  end

  defp restrict_files(query, nil), do: query

  defp restrict_files(query, library_id),
    do: from([file: file] in query, where: file.library_id == ^library_id)

  @impl true
  def get_movie(id) do
    case Repo.one(
           from(movie in MovieSchema,
             where: movie.id == ^id,
             select: movie
           ),
           log: false
         ) do
      nil ->
        {:error, :not_found}

      movie ->
        movie_versions(movie)
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp movie_versions(movie) do
    versions =
      Repo.all(
        from(file in MediaFileSchema,
          join: identification in MovieIdentificationSchema,
          on: identification.media_file_id == file.id,
          where:
            identification.movie_id == ^movie.id and identification.state in [:automatic, :manual],
          order_by: file.id,
          limit: ^(@max_versions + 1),
          select: %MovieVersion{
            id: file.id,
            availability: file.availability,
            size_bytes: file.size_bytes,
            origin: identification.origin,
            needs_review?: identification.needs_review
          }
        ),
        log: false
      )

    if length(versions) > @max_versions,
      do: {:error, :too_many_versions},
      else: {:ok, {MovieMapper.to_movie(movie), versions}}
  end
end
