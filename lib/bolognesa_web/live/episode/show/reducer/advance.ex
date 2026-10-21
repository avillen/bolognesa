defmodule BolognesaWeb.Episode.Show.Reducer.Advance do
  @moduledoc false
  use BolognesaWeb, :verified_routes
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 3, push_navigate: 2, put_flash: 3]
  alias Bolognesa.Series
  alias BolognesaWeb.LiveSupport.PlaybackEvents
  alias BolognesaWeb.Series.Navigation

  @spec call(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def call(socket, params) do
    if current_playback?(socket, params) and is_nil(socket.assigns[:advance_request]) do
      start_advance(socket, params)
    else
      socket
    end
  end

  @spec apply_result(Phoenix.LiveView.Socket.t(), reference(), term()) ::
          Phoenix.LiveView.Socket.t()
  def apply_result(socket, request, result) do
    if socket.assigns[:advance_request] == request do
      finish(socket, result)
    else
      socket
    end
  end

  defp current_playback?(socket, %{"session_id" => id}),
    do: match?(%{id: ^id}, socket.assigns.compatible_session)

  defp current_playback?(socket, %{"file_id" => id}),
    do:
      is_nil(socket.assigns.compatible_session) and
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
      Series.fetch_next_episode(actor, episode_id, file_id)
    end)
  end

  defp stop_completed(socket, %{"session_id" => _id} = params) do
    {:noreply, socket} = PlaybackEvents.handle_event("playback_ended", params, socket)
    socket
  end

  defp stop_completed(socket, _params), do: socket

  defp finish(socket, {:ok, {:ok, episode}}),
    do: push_navigate(socket, to: ~p"/episodes/#{episode.id}?#{advance_params(socket, episode)}")

  defp finish(socket, {:ok, :not_found}), do: assign(socket, :advance_request, nil)

  defp finish(socket, _result),
    do:
      socket
      |> assign(:advance_request, nil)
      |> put_flash(:error, gettext("No se encontró el episodio."))

  defp advance_params(%{assigns: %{detail: %{season: %{id: season_id}}}} = socket, %{
         season_id: season_id
       }),
       do:
         Navigation.episode_params(
           socket.assigns.series_params,
           Map.get(socket.assigns.season_params, :page, 1)
         )

  defp advance_params(socket, _episode), do: Map.get(socket.assigns, :series_params, %{})
end
