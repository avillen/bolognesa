defmodule Bolognesa.Series.Application.UseCases.ListSeriesReviewItems do
  @moduledoc "Authorize the paginated series review queue."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.ReadQuery
  alias Bolognesa.Series.Application.Dto.SeriesReviewItem
  alias Bolognesa.Series.Application.Ports.Readers.SeriesReviewReader
  alias Bolognesa.Series.Application.UseCases.ListSeriesReviewItems.Response, as: SeriesReviewPage

  @spec call(AuthenticatedUser.t(), pos_integer(), SeriesReviewReader.adapter()) ::
          {:ok, SeriesReviewPage.t()} | {:error, :forbidden | :invalid_page | :unavailable}
  def call(actor, page, reader) do
    with :ok <- Accounts.authorize(actor, :admin),
         true <- ReadQuery.valid_page?(page) || {:error, :invalid_page},
         {:ok, {rows, total}} <- reader.list_series_review_items(page) do
      {:ok,
       %SeriesReviewPage{items: Enum.map(rows, &SeriesReviewItem.from_domain/1), total: total}}
    end
  end
end
