defmodule Bolognesa.Music.Domain.Entities.Track do
  @moduledoc "Local musical track."

  alias Bolognesa.Music.Domain.Entities.Album
  alias Bolognesa.Music.Domain.Entities.Artist

  @type id :: pos_integer()

  @type t :: %__MODULE__{
          id: id(),
          media_file_id: pos_integer(),
          library_id: pos_integer(),
          title: String.t(),
          artist_id: Artist.id() | nil,
          album_id: Album.id() | nil,
          disc_number: pos_integer() | nil,
          track_number: pos_integer() | nil,
          year: pos_integer() | nil,
          observed_revision: pos_integer(),
          inspection_token: String.t()
        }

  defstruct [
    :id,
    :media_file_id,
    :library_id,
    :title,
    :artist_id,
    :album_id,
    :disc_number,
    :track_number,
    :year,
    :observed_revision,
    :inspection_token
  ]
end
