defmodule Bolognesa.Identification.Infrastructure.Persistence.EctoReviewReader do
  @moduledoc false
  import Ecto.Query

  alias Bolognesa.Catalog.Infrastructure.Persistence.EctoMovieRepository.MovieSchema

  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository.IdentificationSchema

  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository.MediaFileSchema
  alias Bolognesa.Repo

  @page_size 24

  @spec list_review_items(pos_integer()) :: {:ok, map()} | {:error, :unavailable}
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
          select: %{
            file_id: identification.media_file_id,
            state: identification.state,
            needs_review: identification.needs_review,
            failure_reason: identification.failure_reason,
            availability: file.availability,
            relative_path: file.relative_path,
            movie_id: movie.id,
            movie_title: movie.title,
            candidates: identification.candidate_data
          }
        ),
        log: false
      )

    items =
      Enum.map(rows, fn row ->
        row |> Map.delete(:relative_path) |> Map.put(:filename, safe_basename(row.relative_path))
      end)

    {:ok, %{items: items, total: total}}
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp safe_basename(path) when is_binary(path) do
    name = :filename.basename(path)
    if String.valid?(name), do: name, else: "Archivo"
  end
end
