defmodule Bolognesa.Series.Application.UseCases.SearchSeries.Response do
  @moduledoc "Public series page result."
  alias Bolognesa.Series.Application.UseCases.SearchSeries.Item, as: SeriesListItem
  alias Bolognesa.Series.Domain.ReadModels.Episode
  alias Bolognesa.Series.Domain.ReadModels.Series

  @type t :: %__MODULE__{
          items: [SeriesListItem.t()],
          total: Series.count()
        }

  defstruct [:items, :total]

  @spec from_domain({[{Series.t(), Episode.count(), Episode.count()}], Series.count()}) :: t()
  def from_domain({rows, total}),
    do: %__MODULE__{items: Enum.map(rows, &SeriesListItem.from_domain/1), total: total}
end
