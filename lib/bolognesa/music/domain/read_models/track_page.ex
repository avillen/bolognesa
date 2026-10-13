defmodule Bolognesa.Music.Domain.ReadModels.TrackPage do
  @moduledoc "Bounded music page."
  alias Bolognesa.Music.Domain.ReadModels.TrackRow
  defstruct items: [], total: 0, page: 1, page_size: 50, heading: nil

  @type t :: %__MODULE__{
          items: [TrackRow.t()],
          total: non_neg_integer(),
          page: pos_integer(),
          page_size: pos_integer(),
          heading: String.t() | nil
        }
end
