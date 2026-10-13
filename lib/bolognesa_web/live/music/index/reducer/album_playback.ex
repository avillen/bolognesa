defmodule BolognesaWeb.Music.Index.Reducer.AlbumPlayback do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 3]
  alias Bolognesa.{Music, Playback}
  alias Bolognesa.Music.Application.UseCases.AlbumTracks

  @type async_result :: {:ok, AlbumTracks.queue_result()} | {:exit, term()}
  @type operation ::
          :load
          | {:apply_queue, reference(), async_result()}
          | {:move, -1 | 1}
          | {:ended, String.t()}
  @spec call(Phoenix.LiveView.Socket.t(), operation()) :: Phoenix.LiveView.Socket.t()
  def call(socket, :load), do: load(socket)
  def call(socket, {:apply_queue, request, result}), do: apply_queue(socket, request, result)
  def call(socket, {:move, step}), do: move(socket, step)
  def call(socket, {:ended, generation}), do: ended(socket, generation)

  defp load(socket) do
    actor = socket.assigns.current_scope.actor
    album = socket.assigns.album_id
    library = socket.assigns.active_library_id
    request = make_ref()

    socket
    |> assign(:queue_request, request)
    |> assign(:queue_loading?, true)
    |> start_async({:album_queue, request}, fn -> Music.album_queue(actor, album, library) end)
  end

  defp apply_queue(socket, request, result) do
    if socket.assigns.queue_request == request, do: apply_result(socket, result), else: socket
  end

  defp apply_result(socket, {:ok, {:ok, [_ | _] = tracks}}) do
    socket |> assign(:queue_loading?, false) |> assign(:queue, tracks) |> select(0)
  end

  defp apply_result(socket, {:ok, {:error, :album_too_large}}) do
    socket
    |> assign(:queue_loading?, false)
    |> assign(
      :audio_error,
      gettext("El álbum supera el límite de 500 canciones. Reproduce canciones individuales.")
    )
  end

  defp apply_result(socket, _) do
    socket
    |> assign(:queue_loading?, false)
    |> assign(
      :audio_error,
      gettext("No se pudo cargar el álbum para reproducirlo. Puedes reintentar.")
    )
  end

  defp move(socket, step), do: select(socket, socket.assigns.queue_position + step)

  defp ended(socket, generation) do
    if generation == to_string(socket.assigns.player_generation) and socket.assigns.queue != [] and
         not socket.assigns.player_stopped?, do: move(socket, 1), else: socket
  end

  defp select(socket, position) when position < 0, do: socket

  defp select(socket, position) do
    case Enum.at(socket.assigns.queue, position) do
      nil -> socket |> assign(:queue_finished?, true) |> assign(:player_stopped?, true)
      track -> play(socket, track, position)
    end
  end

  defp play(socket, track, position) do
    socket =
      socket
      |> assign(:queue_position, position)
      |> assign(:queue_finished?, false)
      |> assign(:player_generation, socket.assigns.player_generation + 1)

    case Playback.start_track(socket.assigns.current_scope.actor, track.id, track.file_id) do
      {:ok, _source} ->
        socket
        |> assign(:selected, %{track_id: track.id, file_id: track.file_id, title: track.title})
        |> assign(:player_stopped?, false)
        |> assign(:play_requested?, true)
        |> assign(:audio_error, nil)

      _ ->
        socket
        |> assign(:selected, nil)
        |> assign(:player_stopped?, true)
        |> assign(:play_requested?, false)
        |> assign(
          :audio_error,
          gettext("No se puede reproducir %{title}. Pulsa Siguiente para continuar.",
            title: track.title
          )
        )
    end
  end
end
