defmodule BolognesaWeb.Music.Index.Live do
  @moduledoc false
  use BolognesaWeb, :live_view
  alias BolognesaWeb.Music.Index.Forms.Filters
  alias BolognesaWeb.Music.Index.Reducer.{AlbumPlayback, ApplyPage, Load, Play, RetryImport}
  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:browse_kind, :tracks)
     |> assign(:artist_id, nil)
     |> assign(:album_id, nil)
     |> assign(:heading, nil)
     |> assign(:page_tracks, %{})
     |> assign(:queue, [])
     |> assign(:queue_position, 0)
     |> assign(:queue_loading?, false)
     |> assign(:queue_request, nil)
     |> assign(:queue_finished?, false)
     |> assign(:player_generation, 0)
     |> assign(:player_stopped?, false)
     |> assign(:play_requested?, false)
     |> assign(:browse_params, %{})
     |> assign(:query, "")
     |> assign(:page, 1)
     |> assign(:total, 0)
     |> assign(:page_size, 50)
     |> assign(:loading?, true)
     |> assign(:error, nil)
     |> assign(:request_id, nil)
     |> assign(:selected, nil)
     |> assign(:audio_error, nil)
     |> assign(:form, to_form(%{"query" => ""}, as: :search))
     |> stream(:groups, [])
     |> stream(:tracks, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {query, page} = Filters.from_params(params)
    {kind, artist, album} = Filters.browse(params)

    browse_params =
      socket.assigns.library_params
      |> Map.put(:view, kind)
      |> optional(:artist_id, artist)
      |> optional(:album_id, album)

    {:noreply,
     socket
     |> assign(:browse_kind, kind)
     |> assign(:artist_id, artist)
     |> assign(:album_id, album)
     |> assign(:browse_params, browse_params)
     |> Load.call(query, page)}
  end

  @impl true
  def handle_async({:music_tracks, request_id}, result, socket),
    do: {:noreply, ApplyPage.call(socket, request_id, result)}

  def handle_async({:album_queue, request_id}, result, socket),
    do: {:noreply, AlbumPlayback.call(socket, {:apply_queue, request_id, result})}

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/music?#{Map.put(socket.assigns.browse_params, :query, query)}")}
  end

  def handle_event("play", %{"track_id" => track, "file_id" => file}, socket),
    do: {:noreply, Play.call(socket, track, file)}

  def handle_event("play-album", _params, socket),
    do: {:noreply, AlbumPlayback.call(socket, :load)}

  def handle_event("queue-next", _params, socket),
    do: {:noreply, AlbumPlayback.call(socket, {:move, 1})}

  def handle_event("queue-previous", _params, socket),
    do: {:noreply, AlbumPlayback.call(socket, {:move, -1})}

  def handle_event("audio-ended", %{"generation" => generation}, socket),
    do: {:noreply, AlbumPlayback.call(socket, {:ended, generation})}

  def handle_event("audio-blocked", %{"generation" => generation}, socket) do
    {:noreply,
     audio_feedback(
       socket,
       generation,
       gettext(
         "El navegador ha bloqueado la reproducción automática. Pulsa reproducir en el reproductor para continuar."
       )
     )}
  end

  def handle_event("retry-import", %{"file_id" => file}, socket),
    do: {:noreply, RetryImport.call(socket, file)}

  def handle_event("refresh", _params, socket),
    do: {:noreply, Load.call(socket, socket.assigns.query, socket.assigns.page)}

  def handle_event("audio-error", params, socket) do
    {:noreply,
     audio_feedback(
       socket,
       Map.get(params, "generation", to_string(socket.assigns.player_generation)),
       gettext(
         "El navegador no pudo reproducir este audio. Prueba otro formato o pulsa Siguiente."
       )
     )}
  end

  defp audio_feedback(socket, generation, message) do
    if generation == to_string(socket.assigns.player_generation),
      do: assign(socket, :audio_error, message),
      else: socket
  end

  defp optional(params, _key, nil), do: params
  defp optional(params, key, id), do: Map.put(params, key, id)
end
