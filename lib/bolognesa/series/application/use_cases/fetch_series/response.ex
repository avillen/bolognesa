defmodule Bolognesa.Series.Application.UseCases.FetchSeries.Response do
  @moduledoc "Public series detail result."
  alias Bolognesa.Series.Application.UseCases.FetchSeries.Season, as: SeasonListItem
  alias Bolognesa.Series.Domain.ReadModels.Episode
  alias Bolognesa.Series.Domain.ReadModels.Season
  alias Bolognesa.Series.Domain.ReadModels.Series

  @type t :: %__MODULE__{
          series: Series.t(),
          seasons: [SeasonListItem.t()]
        }

  defstruct [:series, :seasons]

  @spec from_domain({Series.t(), [{Season.t(), Episode.count()}]}) :: t()
  def from_domain({series, seasons}),
    do: %__MODULE__{series: series, seasons: Enum.map(seasons, &SeasonListItem.from_domain/1)}
end
