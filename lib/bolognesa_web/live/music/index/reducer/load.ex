defmodule BolognesaWeb.Music.Index.Reducer.Load do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [start_async: 3]
  alias Bolognesa.Music

  @spec call(Phoenix.LiveView.Socket.t(), String.t(), pos_integer()) ::
          Phoenix.LiveView.Socket.t()
  def call(socket, query, page) do
    actor = socket.assigns.current_scope.actor
    library_id = socket.assigns.active_library_id
    request_id = make_ref()
    kind = socket.assigns.browse_kind
    artist_id = socket.assigns.artist_id
    album_id = socket.assigns.album_id

    socket
    |> assign(:query, query)
    |> assign(:page, page)
    |> assign(:loading?, true)
    |> assign(:error, nil)
    |> assign(:request_id, request_id)
    |> assign(:form, to_form(%{"query" => query}, as: :search))
    |> start_async({:music_tracks, request_id}, fn ->
      read(actor, kind, artist_id, album_id, query, page, library_id)
    end)
  end

  defp read(actor, :tracks, _artist, _album, query, page, library),
    do: Music.list_tracks(actor, query, page, library)

  defp read(actor, :album, _artist, album, query, page, library),
    do: Music.list_album_tracks(actor, album, query, page, library)

  defp read(actor, kind, artist, _album, query, page, library),
    do: Music.browse(actor, kind, artist, query, page, library)
end
