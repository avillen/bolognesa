defmodule BolognesaWeb.Music.Index.Forms.Filters do
  @moduledoc "URL filter parsing for the music screen."
  @spec from_params(map()) :: {String.t(), pos_integer()}
  def from_params(params), do: {Map.get(params, "query", ""), page(Map.get(params, "page", "1"))}

  @spec browse(map()) ::
          {:tracks | :artists | :albums | :album, pos_integer() | nil, pos_integer() | nil}
  def browse(params) do
    kind =
      case Map.get(params, "view") do
        "artists" -> :artists
        "albums" -> :albums
        "album" -> :album
        _ -> :tracks
      end

    {kind, id(Map.get(params, "artist_id")), id(Map.get(params, "album_id"))}
  end

  defp id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> id
      _ -> nil
    end
  end

  defp id(_), do: nil

  defp page(value) when is_binary(value) do
    case Integer.parse(value) do
      {page, ""} when page in 1..100_000 -> page
      _ -> 1
    end
  end

  defp page(_value), do: 1
end
