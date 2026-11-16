defmodule BolognesaWeb.Music.Index.Reducer.RefreshListening do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 3, stream_insert: 3]
  alias Bolognesa.Music
  alias BolognesaWeb.Music.Index.State.Track

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

  @spec flush(Phoenix.LiveView.Socket.t(), term()) :: Phoenix.LiveView.Socket.t()
  def flush(socket, result) do
    pending = socket.assigns.pending_listening
    socket = assign(socket, :pending_listening, MapSet.new())

    case result do
      {:ok, {:ok, _page}} -> Enum.reduce(pending, socket, &call(&2, &1))
      _ -> socket
    end
  end

  defp fetch(socket, track_id) do
    actor = socket.assigns.current_scope.actor
    kind = socket.assigns.browse_kind
    album = socket.assigns.album_id
    query = socket.assigns.query
    page = socket.assigns.page
    library = socket.assigns.active_library_id
    request_id = socket.assigns.request_id

    start_async(socket, {:listening_activity, request_id, track_id}, fn ->
      read(actor, kind, album, query, page, library)
    end)
  end

  defp read(actor, :tracks, _album, query, page, library),
    do: Music.list_tracks(actor, query, page, library)

  defp read(actor, :album, album, query, page, library),
    do: Music.list_album_tracks(actor, album, query, page, library)

  @spec apply_result(Phoenix.LiveView.Socket.t(), reference(), integer(), term()) ::
          Phoenix.LiveView.Socket.t()
  def apply_result(socket, request_id, track_id, {:ok, {:ok, page}}) do
    if socket.assigns.request_id == request_id and
         MapSet.member?(socket.assigns.visible_track_ids, track_id) do
      case Enum.find(page.items, &(&1.id == track_id)) do
        nil -> socket
        track -> stream_insert(socket, :tracks, Track.from_dto(track))
      end
    else
      socket
    end
  end

  def apply_result(socket, _request_id, _track_id, _result), do: socket
end
