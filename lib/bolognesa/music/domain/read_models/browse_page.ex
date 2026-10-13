defmodule Bolognesa.Music.Domain.ReadModels.BrowsePage do
  @moduledoc "Bounded local music browsing projection."
  defstruct [:items, :total, :page, :heading]

  @type t :: %__MODULE__{
          items: [Bolognesa.Music.Domain.ReadModels.BrowseItem.t()],
          total: non_neg_integer(),
          page: pos_integer(),
          heading: String.t() | nil
        }
end
