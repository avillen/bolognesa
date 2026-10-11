defmodule Bolognesa.Catalog.Application.Dto.EpisodePage do
  @moduledoc "Public episode page result."
  alias Bolognesa.Catalog.Application.Dto.EpisodeListItem
  alias Bolognesa.Catalog.Domain.{Episode, EpisodeVersion, Season, Series}

  defstruct [:season, :series, :items, :total]

  @type t :: %__MODULE__{
          season: Season.t(),
          series: Series.t(),
          items: [EpisodeListItem.t()],
          total: Episode.count()
        }

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
