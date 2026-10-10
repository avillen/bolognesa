defmodule Bolognesa.Identification.Application.Dto.ReviewPage do
  @moduledoc "A page of identification review items."

  alias Bolognesa.Identification.Application.Dto.ReviewItem

  @enforce_keys [:items, :total]
  defstruct [:items, :total]

  @type t :: %__MODULE__{items: [ReviewItem.t()], total: non_neg_integer()}
end
