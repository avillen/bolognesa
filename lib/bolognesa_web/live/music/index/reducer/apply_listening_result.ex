defmodule BolognesaWeb.Music.Index.Reducer.ApplyListeningResult do
  @moduledoc false
  import Phoenix.LiveView, only: [stream_insert: 3]
  alias BolognesaWeb.Music.Index.State.Track

  @spec call(Phoenix.LiveView.Socket.t(), reference(), integer(), term()) ::
          Phoenix.LiveView.Socket.t()
  def call(socket, request_id, track_id, {:ok, {:ok, page}}) do
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

  def call(socket, _request_id, _track_id, _result), do: socket
end
