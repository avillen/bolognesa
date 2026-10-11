defmodule Bolognesa.Identification.Application.Dto.SeriesReviewPage do
  @moduledoc "Paginated series identification review."
  alias Bolognesa.Identification.Application.Dto.SeriesReviewItem
  defstruct items: [], total: 0
  @type t :: %__MODULE__{items: [SeriesReviewItem.t()], total: non_neg_integer()}
end
