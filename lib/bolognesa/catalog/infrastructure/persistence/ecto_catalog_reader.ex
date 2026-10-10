defmodule Bolognesa.Catalog.Infrastructure.Persistence.EctoCatalogReader do
  @moduledoc false
  import Ecto.Query

  alias Bolognesa.Catalog.Application.Dto.{
    MovieDetail,
    MovieListItem,
    MoviePage,
    MovieVersion
  }

  alias Bolognesa.Catalog.Infrastructure.Persistence.EctoMovieRepository.MovieMapper
  alias Bolognesa.Catalog.Infrastructure.Persistence.EctoMovieRepository.MovieSchema

  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository.IdentificationSchema

  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository.MediaFileSchema
  alias Bolognesa.Repo

  @page_size 24

  @spec list_movies(binary(), pos_integer()) :: {:ok, MoviePage.t()} | {:error, :unavailable}
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
          group_by: [movie.id, movie.title, movie.year, movie.poster_path],
          order_by: [asc: movie.title, asc: movie.id],
          limit: @page_size,
          offset: ^offset,
          select: %{
            id: movie.id,
            title: movie.title,
            year: movie.year,
            poster_path: movie.poster_path,
            version_count: count(file.id),
            available_count: filter(count(file.id), file.availability == :available)
          }
        ),
        log: false
      )

    {:ok, %MoviePage{items: Enum.map(rows, &struct!(MovieListItem, &1)), total: total}}
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  @spec get_movie(pos_integer()) :: {:ok, MovieDetail.t()} | {:error, :not_found | :unavailable}
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
              select: %{
                id: file.id,
                availability: file.availability,
                size_bytes: file.size_bytes,
                origin: identification.origin,
                needs_review: identification.needs_review
              }
          )

        {:ok,
         %MovieDetail{
           movie: MovieMapper.to_movie(movie),
           versions: Enum.map(versions, &struct!(MovieVersion, &1))
         }}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end
end
