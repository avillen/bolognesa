defmodule Bolognesa.Series.Application.Ports.Readers.SeriesReviewReader do
  @moduledoc "Reads one review row per series file."
  alias Bolognesa.Series.Domain.ReadModels.ReviewEpisode
  alias Bolognesa.Series.Domain.ReadModels.ReviewSeriesFile
  @type adapter :: module()
  @callback fetch_series_review_item(pos_integer()) ::
              {:ok, {ReviewSeriesFile.t(), [ReviewEpisode.t()]}}
              | :not_found
              | {:error, :unavailable}
  @callback list_series_review_items(page :: pos_integer()) ::
              {:ok, {[{ReviewSeriesFile.t(), [ReviewEpisode.t()]}], non_neg_integer()}}
              | {:error, :unavailable}
end
