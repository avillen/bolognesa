defmodule BolognesaWeb.Series.Episode.Reducer.Advance do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 3]
  alias Bolognesa.Series
  alias BolognesaWeb.LiveSupport.PlaybackAttempt
  alias BolognesaWeb.LiveSupport.PlaybackEvents

  @spec call(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def call(%{assigns: %{loading?: true}} = socket, _params), do: socket

  def call(socket, params) do
    if PlaybackAttempt.playing?(socket.assigns.playback, params) and
         is_nil(socket.assigns[:advance_request]) do
      start_advance(socket, params)
    else
      socket
    end
  end

  defp start_advance(socket, params) do
    socket = stop_completed(socket, params)
    actor = socket.assigns.current_scope.actor
    {:episode, episode_id} = socket.assigns.content_ref
    file_id = socket.assigns.playback.file_id
    request = make_ref()

    socket
    |> assign(:advance_request, request)
    |> start_async({:next_episode, request}, fn ->
      Series.fetch_next_playable_episode(actor, episode_id, file_id)
    end)
  end

  defp stop_completed(socket, %{"session_id" => id}), do: PlaybackEvents.ended(socket, id)

  defp stop_completed(socket, _params), do: socket
end
