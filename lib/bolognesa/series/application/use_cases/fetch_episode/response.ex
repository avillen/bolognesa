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
          versions: [EpisodeVersionDto.t()]
        }

  defstruct [:episode, :season, :series, :versions]

  @spec from_domain({Episode.t(), Season.t(), Series.t(), [EpisodeVersion.t()]}) :: t()
  def from_domain({episode, season, series, versions}),
    do: %__MODULE__{
      episode: episode,
      season: season,
      series: series,
      versions: Enum.map(versions, &EpisodeVersionDto.from_domain/1)
    }
end
