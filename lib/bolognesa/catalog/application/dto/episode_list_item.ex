defmodule Bolognesa.Catalog.Application.Dto.EpisodeListItem do
  @moduledoc "Public episode list item projection."
  alias Bolognesa.Catalog.Domain.ReadModels.Series.Episode
  alias Bolognesa.Catalog.Domain.ReadModels.Series.EpisodeVersion
  alias Bolognesa.Catalog.Domain.ReadModels.Series.Season

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

  @type t :: %__MODULE__{
          id: Episode.id(),
          season_id: Season.id(),
          number: pos_integer(),
          title: binary(),
          overview: binary() | nil,
          air_date: Date.t() | nil,
          still_path: binary() | nil,
          version_count: EpisodeVersion.count(),
          available_version_count: EpisodeVersion.count()
        }
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
