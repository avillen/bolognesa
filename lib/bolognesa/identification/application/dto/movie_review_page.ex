defmodule Bolognesa.Identification.Application.Dto.MovieReviewPage do
  @moduledoc "A page of identification review items."

  alias Bolognesa.Identification.Application.Dto.MovieReviewItem

  @enforce_keys [:items, :total]
  defstruct [:items, :total]

  @type t :: %__MODULE__{items: [MovieReviewItem.t()], total: non_neg_integer()}
end
