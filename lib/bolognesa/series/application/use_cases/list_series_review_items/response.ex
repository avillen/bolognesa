defmodule Bolognesa.Series.Application.UseCases.ListSeriesReviewItems.Response do
  @moduledoc "Paginated series identification review."
  alias Bolognesa.Series.Application.Dto.SeriesReviewItem

  @type t :: %__MODULE__{
          items: [SeriesReviewItem.t()],
          total: non_neg_integer()
        }

  defstruct items: [], total: 0
end
