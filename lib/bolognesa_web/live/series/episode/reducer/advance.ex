defmodule BolognesaWeb.Series.Episode.Reducer.Advance do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 3]
  alias Bolognesa.Series
  alias BolognesaWeb.LiveSupport.PlaybackEvents

  @spec call(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def call(%{assigns: %{loading?: true}} = socket, _params), do: socket

  def call(socket, params) do
    if current_playback?(socket, params) and is_nil(socket.assigns[:advance_request]) do
      start_advance(socket, params)
    else
      socket
    end
  end

  defp current_playback?(socket, %{"session_id" => id}),
    do: match?(%{id: ^id}, socket.assigns.transcode_session)

  defp current_playback?(socket, %{"file_id" => id}),
    do:
      socket.assigns.playback_phase == :ready and
        is_nil(socket.assigns.transcode_session) and
        not is_nil(socket.assigns.selected_file_id) and
        is_nil(socket.assigns.playback_error) and to_string(socket.assigns.selected_file_id) == id

  defp current_playback?(_socket, _params), do: false

  defp start_advance(socket, params) do
    socket = stop_completed(socket, params)
    actor = socket.assigns.current_scope.actor
    {:episode, episode_id} = socket.assigns.content_ref
    file_id = socket.assigns.selected_file_id
    request = make_ref()

    socket
    |> assign(:advance_request, request)
    |> start_async({:next_episode, request}, fn ->
      Series.fetch_next_playable_episode(actor, episode_id, file_id)
    end)
  end

  defp stop_completed(socket, %{"session_id" => _id} = params) do
    {:noreply, socket} = PlaybackEvents.handle_event("playback_ended", params, socket)
    socket
  end

  defp stop_completed(socket, _params), do: socket
end
