defmodule Bolognesa.Music.Domain.ReadModels.TrackPage do
  @moduledoc """
  Bounded music page. `has_next?` drives pagination; `total` is the exact count
  only for album pages and `nil` for the uncounted track index.
  """
  alias Bolognesa.Music.Domain.ReadModels.TrackRow

  @type t :: %__MODULE__{
          items: [TrackRow.t()],
          total: non_neg_integer() | nil,
          has_next?: boolean(),
          page: pos_integer(),
          page_size: pos_integer(),
          heading: String.t() | nil,
          album_artist: String.t() | nil,
          album_year: pos_integer() | nil
        }

  defstruct items: [],
            total: nil,
            has_next?: false,
            page: 1,
            page_size: 50,
            heading: nil,
            album_artist: nil,
            album_year: nil
end
