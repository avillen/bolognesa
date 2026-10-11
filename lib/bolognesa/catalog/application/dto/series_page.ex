defmodule Bolognesa.Catalog.Application.Dto.SeriesPage do
  @moduledoc "Public series page result."
  alias Bolognesa.Catalog.Application.Dto.SeriesListItem
  alias Bolognesa.Catalog.Domain.{Episode, Series}

  defstruct [:items, :total]
  @type t :: %__MODULE__{items: [SeriesListItem.t()], total: Series.count()}

  @spec from_domain({[{Series.t(), Episode.count(), Episode.count()}], Series.count()}) :: t()
  def from_domain({rows, total}),
    do: %__MODULE__{items: Enum.map(rows, &SeriesListItem.from_domain/1), total: total}
end
