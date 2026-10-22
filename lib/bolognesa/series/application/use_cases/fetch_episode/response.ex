defmodule Bolognesa.Series.Application.UseCases.FetchEpisode.Response do
  @moduledoc "Public episode detail result."
  alias Bolognesa.Series.Application.UseCases.FetchEpisode.Version, as: EpisodeVersionDto
  alias Bolognesa.Series.Domain.ReadModels.Episode
  alias Bolognesa.Series.Domain.ReadModels.EpisodeVersion
  alias Bolognesa.Series.Domain.ReadModels.Season
  alias Bolognesa.Series.Domain.ReadModels.Series

  @type t :: %__MODULE__{
          episode: Episode.t(),
          season: Season.t(),
          series: Series.t(),
          versions: [EpisodeVersionDto.t()],
          previous_episode_id: Episode.id() | nil,
          next_episode_id: Episode.id() | nil
        }

  defstruct [:episode, :season, :series, :versions, :previous_episode_id, :next_episode_id]

  @spec from_domain(
          {Episode.t(), Season.t(), Series.t(), [EpisodeVersion.t()],
           {Episode.id() | nil, Episode.id() | nil}}
        ) :: t()
  def from_domain({episode, season, series, versions, {previous_id, next_id}}),
    do: %__MODULE__{
      episode: episode,
      season: season,
      series: series,
      versions: Enum.map(versions, &EpisodeVersionDto.from_domain/1),
      previous_episode_id: previous_id,
      next_episode_id: next_id
    }
end
