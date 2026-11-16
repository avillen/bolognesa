defmodule BolognesaWeb.Music.Index.Forms.Filters do
  @moduledoc "URL filter parsing for the music screen."
  alias BolognesaWeb.Params
  @spec from_params(map()) :: {String.t(), pos_integer()}
  def from_params(params), do: {Map.get(params, "query", ""), Params.page(params["page"])}

  @spec browse(map()) ::
          {:home | :tracks | :artists | :albums | :album, pos_integer() | nil,
           pos_integer() | nil}
  def browse(params) do
    kind =
      case Map.get(params, "view") do
        "home" -> :home
        "artists" -> :artists
        "albums" -> :albums
        "album" -> :album
        nil -> :home
        _ -> :tracks
      end

    {kind, Params.positive_integer(params["artist_id"]),
     Params.positive_integer(params["album_id"])}
  end
end
