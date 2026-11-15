defmodule Bolognesa.Series.Application.UseCases.FetchEpisode.Response do
  @moduledoc "Public episode detail result."
  alias Bolognesa.Series.Domain.ReadModels.Episode
  alias Bolognesa.Series.Domain.ReadModels.EpisodeVersion
  alias Bolognesa.Series.Domain.ReadModels.Season
  alias Bolognesa.Series.Domain.ReadModels.Series

  @type t :: %__MODULE__{
          episode: Episode.t(),
          season: Season.t(),
          series: Series.t(),
          versions: [EpisodeVersion.t()],
          previous_entry: Bolognesa.Series.Domain.ReadModels.EpisodeTarget.t() | nil,
          next_entry: Bolognesa.Series.Domain.ReadModels.EpisodeTarget.t() | nil
        }

  defstruct [
    :episode,
    :season,
    :series,
    :versions,
    :previous_entry,
    :next_entry
  ]

  @spec from_domain(
          {Episode.t(), Season.t(), Series.t(), [EpisodeVersion.t()],
           {Bolognesa.Series.Domain.ReadModels.EpisodeTarget.t() | nil,
            Bolognesa.Series.Domain.ReadModels.EpisodeTarget.t() | nil}}
        ) :: t()
  def from_domain({episode, season, series, versions, {previous, next}}),
    do: %__MODULE__{
      episode: episode,
      season: season,
      series: series,
      versions: versions,
      previous_entry: previous,
      next_entry: next
    }
end
