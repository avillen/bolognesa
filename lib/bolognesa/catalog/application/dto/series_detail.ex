defmodule Bolognesa.Catalog.Application.Dto.SeriesDetail do
  @moduledoc "Public series detail result."
  alias Bolognesa.Catalog.Application.Dto.SeasonListItem
  alias Bolognesa.Catalog.Domain.{Episode, Season, Series}

  defstruct [:series, :seasons]
  @type t :: %__MODULE__{series: Series.t(), seasons: [SeasonListItem.t()]}

  @spec from_domain({Series.t(), [{Season.t(), Episode.count()}]}) :: t()
  def from_domain({series, seasons}),
    do: %__MODULE__{series: series, seasons: Enum.map(seasons, &SeasonListItem.from_domain/1)}
end
