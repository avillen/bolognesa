defmodule Bolognesa.Catalog.Application.Dto.EpisodeDetail do
  @moduledoc "Public episode detail result."
  alias Bolognesa.Catalog.Application.Dto.EpisodeVersion
  alias Bolognesa.Catalog.Domain.Episode
  alias Bolognesa.Catalog.Domain.Season
  alias Bolognesa.Catalog.Domain.Series

  defstruct [:episode, :season, :series, :versions]

  @type t :: %__MODULE__{
          episode: Episode.t(),
          season: Season.t(),
          series: Series.t(),
          versions: [EpisodeVersion.t()]
        }
end
