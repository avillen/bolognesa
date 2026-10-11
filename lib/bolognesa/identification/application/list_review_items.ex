defmodule Bolognesa.Identification.Application.ListReviewItems do
  @moduledoc "Authorize paginated identification review."

  alias Bolognesa.Identification.Application.Dto.ReviewItem
  alias Bolognesa.Identification.Application.Dto.ReviewPage
  alias Bolognesa.Identification.Application.Ports.Readers.ReviewReader
  alias Bolognesa.Identity

  @spec call(Bolognesa.Identity.Domain.Actor.t(), pos_integer(), ReviewReader.adapter()) ::
          {:ok, ReviewPage.t()} | {:error, :forbidden | :invalid_page | :unavailable}
  def call(actor, page, reader) do
    with :ok <- Identity.authorize(actor, :admin),
         :ok <- validate_page(page),
         {:ok, {entries, total}} <- reader.list_review_items(page) do
      {:ok, %ReviewPage{items: Enum.map(entries, &ReviewItem.from_domain/1), total: total}}
    end
  end

  defp validate_page(page) when is_integer(page) and page > 0 and page <= 100_000, do: :ok
  defp validate_page(_page), do: {:error, :invalid_page}
end
