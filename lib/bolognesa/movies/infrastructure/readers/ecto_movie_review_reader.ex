defmodule Bolognesa.Movies.Infrastructure.Readers.EctoMovieReviewReader do
  @moduledoc false
  @behaviour Bolognesa.Movies.Application.Ports.Readers.MovieReviewReader

  import Ecto.Query

  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.MovieIdentificationSchema
  alias Bolognesa.Infrastructure.Persistence.MovieSchema
  alias Bolognesa.Movies.Domain.ReadModels.ReviewMovie
  alias Bolognesa.Movies.Domain.ReadModels.ReviewMovieFile
  alias Bolognesa.Movies.Infrastructure.Repositories.IdentificationMapper
  alias Bolognesa.Repo

  @page_size 24

  @impl true
  def list_review_items(page) do
    base =
      from identification in MovieIdentificationSchema,
        join: file in MediaFileSchema,
        on: file.id == identification.media_file_id,
        join: library in LibrarySchema,
        on: library.id == file.library_id,
        where: library.content_type == :movie,
        where:
          identification.state in [:pending, :failed, :unmatched, :manual_unidentified] or
            identification.needs_review == true

    total = Repo.aggregate(base, :count, :id)

    rows =
      Repo.all(
        from(identification in base,
          join: file in MediaFileSchema,
          on: file.id == identification.media_file_id,
          left_join: movie in MovieSchema,
          on: movie.id == identification.movie_id,
          order_by: identification.media_file_id,
          limit: @page_size,
          offset: ^((page - 1) * @page_size),
          select: {identification, file, movie}
        ),
        log: false
      )

    entries =
      Enum.map(rows, fn {identification, file, movie} ->
        {
          IdentificationMapper.to_domain(identification),
          %ReviewMovieFile{
            id: file.id,
            relative_path: file.relative_path,
            availability: file.availability
          },
          to_movie(movie)
        }
      end)

    {:ok, {entries, total}}
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp to_movie(nil), do: nil
  defp to_movie(movie), do: %ReviewMovie{id: movie.id, title: movie.title}
end
