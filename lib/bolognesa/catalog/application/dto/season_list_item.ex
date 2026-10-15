defmodule Bolognesa.Catalog.Application.Dto.SeasonListItem do
  @moduledoc "Public season list item projection."
  alias Bolognesa.Catalog.Domain.ReadModels.Series.Episode
  alias Bolognesa.Catalog.Domain.ReadModels.Series.Season
  alias Bolognesa.Catalog.Domain.ReadModels.Series.Series

  @type t :: %__MODULE__{
          id: Season.id(),
          series_id: Series.id(),
          number: non_neg_integer(),
          title: String.t() | nil,
          poster_path: String.t() | nil,
          episode_count: Episode.count()
        }

  defstruct [:id, :series_id, :number, :title, :poster_path, :episode_count]

  @spec from_domain({Season.t(), Episode.count()}) :: t()
  def from_domain({row, episode_count}),
    do: %__MODULE__{
      id: row.id,
      series_id: row.series_id,
      number: row.number,
      title: row.title,
      poster_path: row.poster_path,
      episode_count: episode_count
    }
end
