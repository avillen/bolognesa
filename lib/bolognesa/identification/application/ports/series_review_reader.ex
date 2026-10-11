defmodule Bolognesa.Identification.Application.Ports.SeriesReviewReader do
  @moduledoc "Reads one review row per series file."
  alias Bolognesa.Identification.Domain.{ReviewEpisode, ReviewSeriesFile}
  @type adapter :: atom()
  @callback list_series_review_items(page :: pos_integer()) ::
              {:ok, {[{ReviewSeriesFile.t(), [ReviewEpisode.t()]}], non_neg_integer()}}
              | {:error, :unavailable}
end
