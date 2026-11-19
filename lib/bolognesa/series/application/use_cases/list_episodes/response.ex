defmodule Bolognesa.Series.Application.UseCases.ListEpisodes.Response do
  @moduledoc "Public episode page result."
  alias Bolognesa.Series.Application.UseCases.ListEpisodes.Item, as: EpisodeListItem
  alias Bolognesa.Series.Domain.ReadModels.Episode
  alias Bolognesa.Series.Domain.ReadModels.EpisodeVersion
  alias Bolognesa.Series.Domain.ReadModels.Season
  alias Bolognesa.Series.Domain.ReadModels.SeasonEntryStatus
  alias Bolognesa.Series.Domain.ReadModels.Series
  alias Bolognesa.Series.Domain.ValueObjects.SeasonEntry

  @type t :: %__MODULE__{
          season: Season.t(),
          series: Series.t(),
          items: [EpisodeListItem.t()],
          total: non_neg_integer()
        }

  defstruct [:season, :series, :items, :total]

  @spec from_domain(
          {Season.t(), Series.t(),
           [{Episode.t(), pos_integer() | nil, EpisodeVersion.count(), EpisodeVersion.count()}],
           Episode.count()},
          [SeasonEntryStatus.t()]
        ) :: t()
  def from_domain({season, series, rows, total}, watched) do
    watched_at =
      Map.new(
        watched,
        &{%SeasonEntry{episode_id: &1.episode_id, part_number: &1.part_number},
         &1.last_watched_at}
      )

    %__MODULE__{
      season: season,
      series: series,
      items:
        Enum.map(rows, fn {episode, part, _, _} = row ->
          entry = %SeasonEntry{episode_id: episode.id, part_number: part}
          EpisodeListItem.from_domain(row, watched_at[entry])
        end),
      total: total
    }
  end
end
