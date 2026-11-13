defmodule Bolognesa.Music.Application.Dto.RecentAlbum do
  @moduledoc "Account-scoped recent album and inferred playback action."
  alias Bolognesa.Music.Domain.Entities.Album
  alias Bolognesa.Music.Domain.Entities.Track
  alias Bolognesa.Music.Domain.ReadModels.RecentAlbum

  @type t :: %__MODULE__{
          id: Album.id(),
          title: String.t(),
          artist: String.t() | nil,
          last_played_at: DateTime.t(),
          track_id: Track.id(),
          file_id: pos_integer(),
          track_title: String.t(),
          track_available?: boolean(),
          restart?: boolean()
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
    :restart?
  ]

  @spec from_domain(RecentAlbum.t()) :: t()
  def from_domain(album) do
    attrs = album |> Map.from_struct() |> Map.delete(:final_track_id)
    struct!(__MODULE__, Map.put(attrs, :restart?, RecentAlbum.restart?(album)))
  end
end
