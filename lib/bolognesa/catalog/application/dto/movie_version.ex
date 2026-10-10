defmodule Bolognesa.Catalog.Application.Dto.MovieVersion do
  @moduledoc "Physical version fields exposed by a catalog movie detail read."

  @enforce_keys [:id, :availability, :size_bytes, :origin, :needs_review]
  defstruct [:id, :availability, :size_bytes, :origin, :needs_review]

  @type t :: %__MODULE__{
          id: pos_integer(),
          availability: :available | :missing,
          size_bytes: non_neg_integer(),
          origin: :automatic | :manual | nil,
          needs_review: boolean()
        }
end
