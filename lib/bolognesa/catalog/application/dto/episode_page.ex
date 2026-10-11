defmodule Bolognesa.Catalog.Application.Dto.EpisodePage do
  @moduledoc "Public episode page result."
  alias Bolognesa.Catalog.Application.Dto.EpisodeListItem
  alias Bolognesa.Catalog.Domain.Episode
  alias Bolognesa.Catalog.Domain.Season
  alias Bolognesa.Catalog.Domain.Series

  defstruct [:season, :series, :items, :total]

  @type t :: %__MODULE__{
          season: Season.t(),
          series: Series.t(),
          items: [EpisodeListItem.t()],
          total: Episode.count()
        }
end
