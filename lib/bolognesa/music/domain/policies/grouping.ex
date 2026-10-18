defmodule Bolognesa.Music.Domain.Policies.Grouping do
  @moduledoc "Conservative, library-local artist and album identities."
  @type album_key :: {pos_integer(), binary(), String.t(), String.t()}

  @spec artist_key(String.t() | nil) :: String.t() | nil
  def artist_key(nil), do: nil

  def artist_key(name) do
    case String.trim(name) do
      "" -> nil
      value -> :string.casefold(value)
    end
  end

  @spec album_key(pos_integer(), binary(), String.t() | nil, String.t() | nil) ::
          album_key() | nil
  def album_key(library_id, parent, album, artist) do
    case artist_key(album) do
      nil -> nil
      title -> {library_id, parent, title, artist_key(artist) || ""}
    end
  end
end
