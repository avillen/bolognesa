defmodule Bolognesa.Catalog.Domain.ReadModels.Movies.MovieVersion do
  @moduledoc "The physical version facts needed by a movie detail read."

  @typedoc "Number of physical versions associated with a movie, including missing files."
  @type count :: non_neg_integer()

  @typedoc "Number of associated physical versions whose files are available."
  @type available_count :: non_neg_integer()

  @type id :: pos_integer()

  @type t :: %__MODULE__{
          id: id(),
          availability: :available | :missing,
          size_bytes: non_neg_integer(),
          origin: :automatic | :manual | nil,
          needs_review?: boolean()
        }

  defstruct [:id, :availability, :size_bytes, :origin, :needs_review?]
end
