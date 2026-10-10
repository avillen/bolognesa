defmodule Bolognesa.Catalog.Domain.MovieVersion do
  @moduledoc "The physical version facts needed by a movie detail read."

  @type t :: %__MODULE__{
          id: pos_integer(),
          availability: :available | :missing,
          size_bytes: non_neg_integer(),
          origin: :automatic | :manual | nil,
          needs_review?: boolean()
        }

  defstruct [:id, :availability, :size_bytes, :origin, :needs_review?]
end
