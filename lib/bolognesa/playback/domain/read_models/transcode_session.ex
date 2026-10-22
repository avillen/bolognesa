defmodule Bolognesa.Playback.Domain.ReadModels.TranscodeSession do
  @moduledoc "Private metadata for one on-demand conversion."

  alias Bolognesa.Playback.Domain.ValueObjects.ContentRef

  @type t :: %__MODULE__{
          id: String.t(),
          actor_id: pos_integer(),
          content_ref: ContentRef.t(),
          file_id: pos_integer(),
          revision: pos_integer(),
          offset_ms: non_neg_integer(),
          duration_ms: non_neg_integer() | nil,
          directory: String.t(),
          strategy: :audio_only | :full_transcode,
          status: :running | :finished | :failed
        }

  defstruct [
    :id,
    :actor_id,
    :content_ref,
    :file_id,
    :revision,
    :offset_ms,
    :duration_ms,
    :directory,
    :strategy,
    status: :running
  ]
end
