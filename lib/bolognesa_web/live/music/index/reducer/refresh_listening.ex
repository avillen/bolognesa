defmodule BolognesaWeb.Music.Index.Reducer.RefreshListening do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [cancel_async: 2, start_async: 3]
  alias Bolognesa.Music

  @spec call(Phoenix.LiveView.Socket.t(), integer()) :: Phoenix.LiveView.Socket.t()
  def call(socket, track_id) do
    cond do
      socket.assigns.browse_kind not in [:tracks, :album] -> socket
      socket.assigns.loading? -> defer(socket, track_id)
      MapSet.member?(socket.assigns.visible_track_ids, track_id) -> fetch(socket, track_id)
      true -> socket
    end
  end

  defp defer(socket, track_id) do
    pending = socket.assigns.pending_listening

    if MapSet.size(pending) < 50,
      do: assign(socket, :pending_listening, MapSet.put(pending, track_id)),
      else: socket
  end

  defp fetch(socket, track_id) do
    actor = socket.assigns.current_scope.actor
    kind = socket.assigns.browse_kind
    album = socket.assigns.album_id
    query = socket.assigns.query
    page = socket.assigns.page
    library = socket.assigns.active_library_id
    key = {:listening_activity, socket.assigns.request_id, track_id}

    socket
    |> cancel_async(key)
    |> start_async(key, fn -> read(actor, kind, album, query, page, library) end)
  end

  defp read(actor, :tracks, _album, query, page, library),
    do: Music.list_tracks(actor, query, page, library)

  defp read(actor, :album, album, query, page, library),
    do: Music.list_album_tracks(actor, album, query, page, library)
end
