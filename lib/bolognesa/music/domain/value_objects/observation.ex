defmodule Bolognesa.Music.Domain.ValueObjects.Observation do
  @moduledoc "Current successful music inspection observed through a read port."
  alias Bolognesa.Libraries.Domain.ValueObjects.Inspection.MusicTags

  @type t :: %__MODULE__{
          file_id: pos_integer(),
          library_id: pos_integer(),
          revision: pos_integer(),
          inspection_token: String.t(),
          relative_path: binary(),
          duration_ms: non_neg_integer() | nil,
          music_tags: MusicTags.t()
        }

  defstruct [
    :file_id,
    :library_id,
    :revision,
    :inspection_token,
    :relative_path,
    :duration_ms,
    :music_tags
  ]
end
