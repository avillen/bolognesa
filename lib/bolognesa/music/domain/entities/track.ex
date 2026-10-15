defmodule Bolognesa.Music.Domain.Entities.Track do
  @moduledoc "Local musical track."

  @type t :: %__MODULE__{
          id: pos_integer(),
          media_file_id: pos_integer(),
          library_id: pos_integer(),
          title: String.t(),
          artist_id: pos_integer(),
          album_id: pos_integer(),
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
