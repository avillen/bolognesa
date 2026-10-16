defmodule Bolognesa.Series.Application.UseCases.ListEpisodes.Response do
  @moduledoc "Public episode page result."
  alias Bolognesa.Series.Application.UseCases.ListEpisodes.Item, as: EpisodeListItem
  alias Bolognesa.Series.Domain.ReadModels.Episode
  alias Bolognesa.Series.Domain.ReadModels.EpisodeVersion
  alias Bolognesa.Series.Domain.ReadModels.Season
  alias Bolognesa.Series.Domain.ReadModels.Series

  @type t :: %__MODULE__{
          season: Season.t(),
          series: Series.t(),
          items: [EpisodeListItem.t()],
          total: Episode.count()
        }

  defstruct [:season, :series, :items, :total]

  @spec from_domain(
          {Season.t(), Series.t(),
           [{Episode.t(), EpisodeVersion.count(), EpisodeVersion.count()}], Episode.count()}
        ) :: t()
  def from_domain({season, series, rows, total}),
    do: %__MODULE__{
      season: season,
      series: series,
      items: Enum.map(rows, &EpisodeListItem.from_domain/1),
      total: total
    }
end
