defmodule Bolognesa.Identification.Application.ListReviewItems do
  @moduledoc "Authorize paginated identification review."

  alias Bolognesa.Identification.Application.Dto.ReviewItem
  alias Bolognesa.Identification.Application.Dto.ReviewPage
  alias Bolognesa.Identification.Application.Ports.ReviewReader
  alias Bolognesa.Identification.Domain.Identification
  alias Bolognesa.Identification.Domain.ReviewFile
  alias Bolognesa.Identification.Domain.ReviewMovie
  alias Bolognesa.Identity

  @spec call(Bolognesa.Identity.Domain.Actor.t(), pos_integer(), ReviewReader.adapter()) ::
          {:ok, ReviewPage.t()} | {:error, :forbidden | :invalid_page | :unavailable}
  def call(actor, page, reader) do
    with :ok <- Identity.authorize(actor, :admin),
         :ok <- validate_page(page),
         {:ok, {entries, total}} <- reader.list_review_items(page) do
      {:ok, %ReviewPage{items: Enum.map(entries, &to_review_item/1), total: total}}
    end
  end

  defp validate_page(page) when is_integer(page) and page > 0 and page <= 100_000, do: :ok
  defp validate_page(_page), do: {:error, :invalid_page}

  defp to_review_item({%Identification{} = decision, %ReviewFile{} = file, movie}) do
    {movie_id, movie_title} = movie_details(movie)

    %ReviewItem{
      file_id: file.id,
      state: decision.state,
      needs_review: decision.needs_review?,
      failure_reason: decision.failure_reason,
      availability: file.availability,
      filename: safe_basename(file.relative_path),
      movie_id: movie_id,
      movie_title: movie_title,
      candidates: decision.candidate_data
    }
  end

  defp movie_details(nil), do: {nil, nil}
  defp movie_details(%ReviewMovie{id: id, title: title}), do: {id, title}

  defp safe_basename(path) when is_binary(path) do
    name = :filename.basename(path)
    if String.valid?(name), do: name, else: "Archivo"
  end
end
