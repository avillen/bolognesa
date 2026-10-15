defmodule Bolognesa.Catalog.Application.Dto.SeriesListItem do
  @moduledoc "Public series list item projection."
  alias Bolognesa.Catalog.Domain.ReadModels.Series.Episode
  alias Bolognesa.Catalog.Domain.ReadModels.Series.Series

  @type t :: %__MODULE__{
          id: Series.id(),
          provider: :tmdb,
          provider_id: pos_integer(),
          title: String.t(),
          year: integer() | nil,
          overview: String.t() | nil,
          poster_path: String.t() | nil,
          backdrop_path: String.t() | nil,
          episode_count: Episode.count(),
          available_episode_count: Episode.count()
        }

  defstruct [
    :id,
    :provider,
    :provider_id,
    :title,
    :year,
    :overview,
    :poster_path,
    :backdrop_path,
    :episode_count,
    :available_episode_count
  ]

  @spec from_domain({Series.t(), Episode.count(), Episode.count()}) :: t()
  def from_domain({row, episode_count, available_episode_count}),
    do: %__MODULE__{
      id: row.id,
      provider: row.provider,
      provider_id: row.provider_id,
      title: row.title,
      year: row.year,
      overview: row.overview,
      poster_path: row.poster_path,
      backdrop_path: row.backdrop_path,
      episode_count: episode_count,
      available_episode_count: available_episode_count
    }
end
