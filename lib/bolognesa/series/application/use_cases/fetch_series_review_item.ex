defmodule Bolognesa.Series.Application.UseCases.FetchSeriesReviewItem do
  @moduledoc "Authorize correction of a series file, including files outside the review queue."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Series.Application.Dto.SeriesReviewItem
  alias Bolognesa.Series.Application.Ports.Readers.SeriesReviewReader

  @spec call(AuthenticatedUser.t(), pos_integer(), SeriesReviewReader.adapter()) ::
          {:ok, SeriesReviewItem.t()} | :not_found | {:error, :forbidden | :unavailable}
  def call(actor, id, reader) do
    with :ok <- Accounts.authorize(actor, :admin),
         :ok <- valid_id(id),
         {:ok, row} <- reader.fetch_series_review_item(id) do
      {:ok, SeriesReviewItem.from_domain(row)}
    end
  end

  defp valid_id(id) when is_integer(id) and id > 0, do: :ok
  defp valid_id(_), do: :not_found
end
