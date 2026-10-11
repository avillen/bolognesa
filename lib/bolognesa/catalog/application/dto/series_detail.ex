defmodule Bolognesa.Catalog.Application.Dto.SeriesDetail do
  @moduledoc "Public series detail result."
  alias Bolognesa.Catalog.Application.Dto.SeasonListItem
  alias Bolognesa.Catalog.Domain.Series

  defstruct [:series, :seasons]
  @type t :: %__MODULE__{series: Series.t(), seasons: [SeasonListItem.t()]}
end
