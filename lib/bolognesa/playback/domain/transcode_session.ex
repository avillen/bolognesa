defmodule Bolognesa.Playback.Domain.TranscodeSession do
  @moduledoc "Private metadata for one on-demand conversion."

  @type t :: %__MODULE__{
          id: String.t(),
          actor_id: pos_integer(),
          catalog_entry_id: pos_integer(),
          file_id: pos_integer(),
          revision: pos_integer(),
          offset_ms: non_neg_integer(),
          duration_ms: non_neg_integer() | nil,
          directory: String.t(),
          profile: :audio | :video,
          status: :running | :finished | :failed
        }

  defstruct [
    :id,
    :actor_id,
    :catalog_entry_id,
    :file_id,
    :revision,
    :offset_ms,
    :duration_ms,
    :directory,
    :profile,
    status: :running
  ]
end
