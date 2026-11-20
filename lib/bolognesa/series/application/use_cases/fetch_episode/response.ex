defmodule Bolognesa.Series.Application.UseCases.FetchEpisode.Response do
  @moduledoc "Public episode detail result, with the entries of its season in order."
  alias Bolognesa.Series.Domain.ReadModels.EntryStatus
  alias Bolognesa.Series.Domain.ReadModels.Episode
  alias Bolognesa.Series.Domain.ReadModels.EpisodeVersion
  alias Bolognesa.Series.Domain.ReadModels.Season
  alias Bolognesa.Series.Domain.ReadModels.Series

  @type t :: %__MODULE__{
          episode: Episode.t(),
          season: Season.t(),
          series: Series.t(),
          versions: [EpisodeVersion.t()],
          entries: [EntryStatus.t()]
        }

  defstruct [:episode, :season, :series, :versions, entries: []]

  @spec from_domain(
          {Episode.t(), Season.t(), Series.t(), [EpisodeVersion.t()]},
          [EntryStatus.t()]
        ) :: t()
  def from_domain({episode, season, series, versions}, entries),
    do: %__MODULE__{
      episode: episode,
      season: season,
      series: series,
      versions: versions,
      entries: entries
    }
end
