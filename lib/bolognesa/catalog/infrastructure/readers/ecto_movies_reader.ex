defmodule Bolognesa.Catalog.Infrastructure.Readers.EctoMoviesReader do
  @moduledoc false
  @behaviour Bolognesa.Catalog.Application.Ports.Readers.MoviesReader

  import Ecto.Query

  alias Bolognesa.Catalog.Domain.ReadModels.Movies.MovieVersion
  alias Bolognesa.Catalog.Infrastructure.Readers.EctoMoviesReader.MovieMapper
  alias Bolognesa.Infrastructure.Persistence.CatalogEntrySchema
  alias Bolognesa.Infrastructure.Persistence.IdentificationEntrySchema
  alias Bolognesa.Infrastructure.Persistence.IdentificationSchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.MovieSchema
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
          join: entry in CatalogEntrySchema,
          on: entry.id == movie.id and entry.kind == :movie,
          left_join: relation in IdentificationEntrySchema,
          on: relation.catalog_entry_id == movie.id,
          left_join: identification in IdentificationSchema,
          on:
            identification.id == relation.identification_id and
              identification.state in [:automatic, :manual],
          left_join: file in MediaFileSchema,
          on: file.id == identification.media_file_id,
          group_by: [movie.id, entry.id],
          order_by: [asc: movie.title, asc: movie.id],
          limit: @page_size,
          offset: ^offset,
          select:
            {movie, entry, count(file.id),
             filter(count(file.id), file.availability == :available)}
        ),
        log: false
      )

    entries =
      Enum.map(rows, fn {movie, entry, version_count, available_count} ->
        {MovieMapper.to_movie(movie, entry), version_count, available_count}
      end)

    {:ok, {entries, total}}
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  @impl true
  def get_movie(id) do
    case Repo.one(
           from(movie in MovieSchema,
             join: entry in CatalogEntrySchema,
             on: entry.id == movie.id and entry.kind == :movie,
             where: movie.id == ^id,
             select: {movie, entry}
           ),
           log: false
         ) do
      nil ->
        {:error, :not_found}

      {movie, entry} ->
        versions =
          Repo.all(
            from file in MediaFileSchema,
              join: identification in IdentificationSchema,
              on: identification.media_file_id == file.id,
              join: relation in IdentificationEntrySchema,
              on: relation.identification_id == identification.id,
              where:
                relation.catalog_entry_id == ^id and identification.state in [:automatic, :manual],
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

        {:ok, {MovieMapper.to_movie(movie, entry), entries}}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end
end
