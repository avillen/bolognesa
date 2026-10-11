defmodule Bolognesa.Identification.Application.UseCases.ListMovieReviewItems do
  @moduledoc "Authorize paginated identification review."

  alias Bolognesa.Identification.Application.Dto.MovieReviewItem
  alias Bolognesa.Identification.Application.Dto.MovieReviewPage
  alias Bolognesa.Identification.Application.Ports.Readers.MovieReviewReader
  alias Bolognesa.Identity

  @spec call(
          Bolognesa.Identity.Domain.Entities.Actor.t(),
          pos_integer(),
          MovieReviewReader.adapter()
        ) ::
          {:ok, MovieReviewPage.t()} | {:error, :forbidden | :invalid_page | :unavailable}
  def call(actor, page, reader) do
    with :ok <- Identity.authorize(actor, :admin),
         :ok <- validate_page(page),
         {:ok, {entries, total}} <- reader.list_review_items(page) do
      {:ok,
       %MovieReviewPage{items: Enum.map(entries, &MovieReviewItem.from_domain/1), total: total}}
    end
  end

  defp validate_page(page) when is_integer(page) and page > 0 and page <= 100_000, do: :ok
  defp validate_page(_page), do: {:error, :invalid_page}
end
