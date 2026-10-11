defmodule Bolognesa.Catalog.Application.Dto.SeriesPage do
  @moduledoc "Public series page result."
  alias Bolognesa.Catalog.Application.Dto.SeriesListItem
  alias Bolognesa.Catalog.Domain.Series

  defstruct [:items, :total]
  @type t :: %__MODULE__{items: [SeriesListItem.t()], total: Series.count()}
end
