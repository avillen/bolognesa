defmodule BolognesaWeb.Music.Index.Reducer.Play do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]
  alias Bolognesa.Playback
  @spec call(Phoenix.LiveView.Socket.t(), String.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def call(socket, track_text, file_text) do
    with {track_id, ""} <- Integer.parse(track_text),
         {file_id, ""} <- Integer.parse(file_text),
         {:ok, _source} <-
           Playback.start_track(socket.assigns.current_scope.actor, track_id, file_id) do
      socket
      |> assign(:selected, %{
        track_id: track_id,
        file_id: file_id,
        title: get_in(socket.assigns.page_tracks, [track_id, :title]),
        artist: get_in(socket.assigns.page_tracks, [track_id, :artist])
      })
      |> assign(:queue, [])
      |> assign(:queue_position, 0)
      |> assign(:queue_request, nil)
      |> assign(:queue_loading?, false)
      |> assign(:queue_finished?, false)
      |> assign(:player_generation, socket.assigns.player_generation + 1)
      |> assign(:player_stopped?, false)
      |> assign(:play_requested?, true)
      |> assign(:audio_error, nil)
    else
      _error ->
        put_flash(
          socket,
          :error,
          gettext("La canción ya no está disponible. Actualiza la lista.")
        )
    end
  end
end
