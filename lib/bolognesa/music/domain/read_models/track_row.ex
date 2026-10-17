defmodule Bolognesa.Music.Domain.ReadModels.TrackRow do
  @moduledoc "Music list item including processing state."

  @type failure_reason ::
          Bolognesa.Music.Domain.Entities.ImportState.failure_reason()
          | :source_changed
          | :source_inaccessible
          | :unsafe_entry
          | :unreadable
          | :unsupported
          | :timeout
          | :tool_unavailable
          | :invalid_output

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          file_id: pos_integer(),
          title: String.t(),
          artist: String.t() | nil,
          album: String.t() | nil,
          duration_ms: non_neg_integer() | nil,
          state: :pending | :ready | :inspection_failed | :import_failed,
          failure_reason: failure_reason() | nil,
          disc_number: pos_integer() | nil,
          track_number: pos_integer() | nil
        }

  defstruct [
    :id,
    :file_id,
    :title,
    :artist,
    :album,
    :duration_ms,
    :state,
    :failure_reason,
    :disc_number,
    :track_number
  ]
end
