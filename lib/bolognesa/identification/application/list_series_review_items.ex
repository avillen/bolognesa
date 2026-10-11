defmodule Bolognesa.Identification.Application.ListSeriesReviewItems do
  @moduledoc "Authorize the paginated series review queue."
  alias Bolognesa.Identification.Application.Dto.{SeriesReviewItem, SeriesReviewPage}
  alias Bolognesa.Identification.Application.Ports.Readers.SeriesReviewReader
  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Actor

  @spec call(Actor.t(), pos_integer(), SeriesReviewReader.adapter()) ::
          {:ok, SeriesReviewPage.t()} | {:error, :forbidden | :invalid_page | :unavailable}
  def call(actor, page, reader) do
    with :ok <- Identity.authorize(actor, :admin),
         :ok <- valid_page(page),
         {:ok, {rows, total}} <- reader.list_series_review_items(page) do
      {:ok,
       %SeriesReviewPage{items: Enum.map(rows, &SeriesReviewItem.from_domain/1), total: total}}
    end
  end

  defp valid_page(page) when is_integer(page) and page in 1..100_000, do: :ok
  defp valid_page(_), do: {:error, :invalid_page}
end
