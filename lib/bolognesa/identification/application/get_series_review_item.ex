defmodule Bolognesa.Identification.Application.GetSeriesReviewItem do
  @moduledoc "Authorize correction of a series file, including files outside the review queue."
  alias Bolognesa.Identification.Application.Dto.SeriesReviewItem
  alias Bolognesa.Identification.Application.Ports.Readers.SeriesReviewReader
  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Actor

  @spec call(Actor.t(), pos_integer(), SeriesReviewReader.adapter()) ::
          {:ok, SeriesReviewItem.t()} | {:error, :forbidden | :not_found | :unavailable}
  def call(actor, id, reader) do
    with :ok <- Identity.authorize(actor, :admin),
         :ok <- valid_id(id),
         {:ok, row} <- reader.get_series_review_item(id) do
      {:ok, SeriesReviewItem.from_domain(row)}
    end
  end

  defp valid_id(id) when is_integer(id) and id > 0, do: :ok
  defp valid_id(_), do: {:error, :not_found}
end
