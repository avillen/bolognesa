defmodule Bolognesa.Music.Domain.ReadModels.RecentAlbum do
  @moduledoc "An album's latest account activity and current continuation selection."
  @type t :: %__MODULE__{
          id: pos_integer(),
          title: String.t(),
          artist: String.t() | nil,
          last_played_at: DateTime.t(),
          track_id: pos_integer(),
          file_id: pos_integer(),
          track_title: String.t(),
          track_available?: boolean(),
          final_track_id: pos_integer()
        }
  defstruct [
    :id,
    :title,
    :artist,
    :last_played_at,
    :track_id,
    :file_id,
    :track_title,
    :track_available?,
    :final_track_id
  ]

  @doc "Replay is a selection heuristic, not evidence that the album was completed."
  @spec restart?(t()) :: boolean()
  def restart?(album), do: album.track_id == album.final_track_id
end
