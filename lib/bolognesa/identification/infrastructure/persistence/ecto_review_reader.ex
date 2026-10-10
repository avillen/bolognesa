defmodule Bolognesa.Identification.Infrastructure.Persistence.EctoReviewReader do
  @moduledoc false
  @behaviour Bolognesa.Identification.Application.Ports.ReviewReader

  import Ecto.Query

  alias Bolognesa.Catalog.Infrastructure.Persistence.EctoMovieRepository.MovieMapper
  alias Bolognesa.Identification.Infrastructure.Persistence.IdentificationMapper
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository.MediaFileMapper
  alias Bolognesa.Persistence.MovieSchema
  alias Bolognesa.Persistence.IdentificationSchema
  alias Bolognesa.Persistence.MediaFileSchema
  alias Bolognesa.Repo

  @page_size 24

  @impl true
  def list_review_items(page) do
    base =
      from identification in IdentificationSchema,
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
          MediaFileMapper.to_media_file(file),
          to_movie(movie)
        }
      end)

    {:ok, {entries, total}}
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp to_movie(nil), do: nil
  defp to_movie(movie), do: MovieMapper.to_movie(movie)
end
