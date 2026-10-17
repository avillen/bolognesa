defmodule Bolognesa.Music.Domain.ValueObjects.MusicTags do
  @moduledoc "Sanitized tag facts used by the local music catalog."

  @type t :: %__MODULE__{
          title: String.t() | nil,
          artist: String.t() | nil,
          album_artist: String.t() | nil,
          album: String.t() | nil,
          disc_number: pos_integer() | nil,
          track_number: pos_integer() | nil,
          year: pos_integer() | nil
        }

  defstruct [:title, :artist, :album_artist, :album, :disc_number, :track_number, :year]
end
