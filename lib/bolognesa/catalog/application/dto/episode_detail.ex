defmodule Bolognesa.Catalog.Application.Dto.EpisodeDetail do
  @moduledoc "Public episode detail result."
  alias Bolognesa.Catalog.Application.Dto.EpisodeVersion, as: EpisodeVersionDto
  alias Bolognesa.Catalog.Domain.ReadModels.Series.Episode
  alias Bolognesa.Catalog.Domain.ReadModels.Series.EpisodeVersion
  alias Bolognesa.Catalog.Domain.ReadModels.Series.Season
  alias Bolognesa.Catalog.Domain.ReadModels.Series.Series

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
