defmodule Bolognesa.Catalog.Infrastructure.Persistence.EctoCatalogReader do
  @moduledoc false
  @behaviour Bolognesa.Catalog.Application.Ports.CatalogReader

  import Ecto.Query

  alias Bolognesa.Catalog.Domain.MovieVersion
  alias Bolognesa.Catalog.Infrastructure.Persistence.EctoMovieRepository.MovieMapper
  alias Bolognesa.Persistence.IdentificationSchema
  alias Bolognesa.Persistence.MediaFileSchema
  alias Bolognesa.Persistence.MovieSchema
  alias Bolognesa.Repo

  @page_size 24

  @impl true
  def list_movies(query, page) do
    filtered =
      from movie in MovieSchema,
        where: fragment("strpos(lower(?), lower(?)) > 0", movie.title, ^query)

    total = Repo.aggregate(filtered, :count, :id, log: false)
    offset = (page - 1) * @page_size

    rows =
      Repo.all(
        from(movie in filtered,
          left_join: identification in IdentificationSchema,
          on: identification.movie_id == movie.id,
          left_join: file in MediaFileSchema,
          on: file.id == identification.media_file_id,
          group_by: movie.id,
          order_by: [asc: movie.title, asc: movie.id],
          limit: @page_size,
          offset: ^offset,
          select: {movie, count(file.id), filter(count(file.id), file.availability == :available)}
        ),
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

  @impl true
  def get_movie(id) do
    case Repo.get(MovieSchema, id) do
      nil ->
        {:error, :not_found}

      movie ->
        versions =
          Repo.all(
            from file in MediaFileSchema,
              join: identification in IdentificationSchema,
              on: identification.media_file_id == file.id,
              where: identification.movie_id == ^id,
              order_by: file.id,
              select: {file, identification}
          )

        entries =
          Enum.map(versions, fn {file, identification} ->
            %MovieVersion{
              id: file.id,
              availability: file.availability,
              size_bytes: file.size_bytes,
              origin: identification.origin,
              needs_review?: identification.needs_review
            }
          end)

        {:ok, {MovieMapper.to_movie(movie), entries}}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end
end
