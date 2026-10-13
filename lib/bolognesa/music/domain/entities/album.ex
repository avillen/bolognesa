defmodule Bolognesa.Music.Domain.Entities.Album do
  @moduledoc "Local musical album."
  defstruct [
    :id,
    :library_id,
    :source_parent,
    :title,
    :normalized_title,
    :artist_id,
    :album_artist_key,
    :year
  ]

  @type t :: %__MODULE__{
          id: pos_integer(),
          library_id: pos_integer(),
          source_parent: binary(),
          title: String.t(),
          normalized_title: String.t(),
          artist_id: pos_integer(),
          album_artist_key: String.t(),
          year: pos_integer() | nil
        }
end
