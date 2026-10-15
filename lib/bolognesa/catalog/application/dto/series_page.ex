defmodule Bolognesa.Catalog.Application.Dto.SeriesPage do
  @moduledoc "Public series page result."
  alias Bolognesa.Catalog.Application.Dto.SeriesListItem
  alias Bolognesa.Catalog.Domain.ReadModels.Series.Episode
  alias Bolognesa.Catalog.Domain.ReadModels.Series.Series

  @type t :: %__MODULE__{
          items: [SeriesListItem.t()],
          total: Series.count()
        }

  defstruct [:items, :total]

  @spec from_domain({[{Series.t(), Episode.count(), Episode.count()}], Series.count()}) :: t()
  def from_domain({rows, total}),
    do: %__MODULE__{items: Enum.map(rows, &SeriesListItem.from_domain/1), total: total}
end
