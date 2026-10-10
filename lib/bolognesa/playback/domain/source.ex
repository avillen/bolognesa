defmodule Bolognesa.Playback.Domain.Source do
  @moduledoc "A physical source authorized for direct playback."

  @type t :: %__MODULE__{
          path: String.t(),
          relative_path: binary(),
          size_bytes: non_neg_integer(),
          modified_at: DateTime.t(),
          revision: pos_integer() | nil,
          format: String.t() | nil,
          duration_ms: non_neg_integer() | nil,
          tracks: [Bolognesa.Playback.Domain.TechnicalTrack.t()]
        }

  defstruct [
    :path,
    :relative_path,
    :size_bytes,
    :modified_at,
    :revision,
    :format,
    :duration_ms,
    tracks: []
  ]
end
