defmodule Bolognesa.Music.Domain.Entities.Track do
  @moduledoc "Local musical track."
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

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          media_file_id: pos_integer() | nil,
          library_id: pos_integer() | nil,
          title: String.t() | nil,
          artist_id: pos_integer() | nil,
          album_id: pos_integer() | nil,
          disc_number: pos_integer() | nil,
          track_number: pos_integer() | nil,
          year: pos_integer() | nil,
          observed_revision: pos_integer() | nil,
          inspection_token: String.t() | nil
        }
end
