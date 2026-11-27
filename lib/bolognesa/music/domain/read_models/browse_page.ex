defmodule Bolognesa.Music.Domain.ReadModels.BrowsePage do
  @moduledoc "Bounded local music browsing projection; `has_next?` replaces an exact count."

  @type t :: %__MODULE__{
          items: [Bolognesa.Music.Domain.ReadModels.BrowseItem.t()],
          has_next?: boolean(),
          page: pos_integer(),
          heading: String.t() | nil
        }

  defstruct [:items, :page, :heading, has_next?: false]
end
