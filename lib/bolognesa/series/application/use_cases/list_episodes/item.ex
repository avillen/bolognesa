defmodule Bolognesa.Series.Application.UseCases.ListEpisodes.Item do
  @moduledoc "Public episode list item projection."
  alias Bolognesa.Series.Domain.ReadModels.Episode
  alias Bolognesa.Series.Domain.ReadModels.EpisodeVersion
  alias Bolognesa.Series.Domain.ReadModels.Season

  @type t :: %__MODULE__{
          id: Episode.id(),
          season_id: Season.id(),
          number: pos_integer(),
          title: String.t(),
          overview: String.t() | nil,
          air_date: Date.t() | nil,
          still_path: String.t() | nil,
          version_count: EpisodeVersion.count(),
          available_version_count: EpisodeVersion.count()
        }

  defstruct [
    :id,
    :season_id,
    :number,
    :title,
    :overview,
    :air_date,
    :still_path,
    :version_count,
    :available_version_count
  ]

  @spec from_domain({Episode.t(), EpisodeVersion.count(), EpisodeVersion.count()}) :: t()
  def from_domain({row, version_count, available_version_count}),
    do: %__MODULE__{
      id: row.id,
      season_id: row.season_id,
      number: row.number,
      title: row.title,
      overview: row.overview,
      air_date: row.air_date,
      still_path: row.still_path,
      version_count: version_count,
      available_version_count: available_version_count
    }
end
