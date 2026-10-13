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
          id: pos_integer() | nil,
          library_id: pos_integer() | nil,
          source_parent: binary(),
          title: String.t() | nil,
          normalized_title: String.t() | nil,
          artist_id: pos_integer() | nil,
          album_artist_key: String.t() | nil,
          year: pos_integer() | nil
        }
end
