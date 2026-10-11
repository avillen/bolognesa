defmodule BolognesaWeb.Movie.Show.Live do
  @moduledoc false
  use BolognesaWeb, :live_view
  alias Bolognesa.Playback
  alias BolognesaWeb.Movie.Show.Reducer

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_scope.actor
    {:ok, Reducer.Initialize.call(socket, actor, parse_id(id))}
  end

  @impl true
  def handle_async({:movie, request_id}, result, socket) do
    {:noreply, Reducer.ApplyResult.call(socket, request_id, result)}
  end

  @impl true
  def handle_event("play", %{"file_id" => file_id}, socket) do
    {:noreply, Reducer.SelectVersion.call(socket, file_id)}
  end

  def handle_event("playback_error", %{"file_id" => file_id}, socket) do
    {:noreply, Reducer.PlaybackError.call(socket, file_id)}
  end

  def handle_event("compatible", %{"file_id" => file_id}, socket) do
    if socket.assigns.selected_file_id &&
         Integer.to_string(socket.assigns.selected_file_id) == file_id do
      Reducer.SelectVersion.stop_previous(socket)
      actor = socket.assigns.current_scope.actor
      movie_id = socket.assigns.detail.movie.id

      {:noreply,
       Reducer.SelectVersion.start_compatible(
         socket,
         actor,
         movie_id,
         socket.assigns.selected_file_id,
         0,
         :video
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "playback_seek",
        %{"session_id" => id, "position_ms" => position} = params,
        socket
      ) do
    session = socket.assigns.compatible_session

    case parse_position(position) do
      {offset, ""}
      when not is_nil(session) and session.id == id and offset >= 0 and
             (is_nil(session.duration_ms) or offset <= session.duration_ms) ->
        Reducer.SelectVersion.stop_previous(socket)
        actor = socket.assigns.current_scope.actor
        movie_id = socket.assigns.detail.movie.id

        next =
          Reducer.SelectVersion.start_compatible(
            socket,
            actor,
            movie_id,
            session.file_id,
            offset,
            if(session.profile == :video, do: :video, else: :auto)
          )

        {:noreply,
         Phoenix.Component.assign(next, :compatible_autoplay?, params["playing"] == "true")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("playback_pause", %{"session_id" => id}, socket) do
    case socket.assigns.compatible_session do
      %{id: ^id} ->
        Playback.pause_compatible(socket.assigns.current_scope.actor, id)
        {:noreply, Phoenix.Component.assign(socket, :compatible_paused?, true)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("playback_resume", %{"session_id" => id, "position_ms" => position}, socket) do
    case socket.assigns.compatible_session do
      %{id: ^id} = session ->
        case Playback.resume_compatible(socket.assigns.current_scope.actor, id) do
          :ok -> {:noreply, Phoenix.Component.assign(socket, :compatible_paused?, false)}
          _ -> resume_expired(socket, session, position)
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("compatible_error", %{"session_id" => id}, socket) do
    case socket.assigns.compatible_session do
      %{id: ^id} ->
        Playback.stop_compatible(socket.assigns.current_scope.actor, id)

        {:noreply,
         socket
         |> Phoenix.Component.assign(
           :playback_error,
           "La conversión se ha interrumpido. Vuelve a intentarlo."
         )
         |> Phoenix.Component.assign(:playback_error_reason, "transcode_failed")}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:compatible_poll, id}, socket) do
    case socket.assigns.compatible_session do
      %{id: ^id} -> poll_compatible(socket, id)
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:compatible_session], do: Reducer.SelectVersion.stop_previous(socket)
    :ok
  end

  defp poll_compatible(socket, id) do
    case Playback.compatible_status(id) do
      :ready ->
        Playback.pause_compatible(socket.assigns.current_scope.actor, id)

        {:noreply,
         socket
         |> Phoenix.Component.assign(:compatible_ready?, true)
         |> Phoenix.Component.assign(:compatible_paused?, true)}

      :waiting ->
        if socket.assigns.compatible_poll_attempts < 60 do
          Process.send_after(self(), {:compatible_poll, id}, 500)

          {:noreply,
           Phoenix.Component.assign(
             socket,
             :compatible_poll_attempts,
             socket.assigns.compatible_poll_attempts + 1
           )}
        else
          Playback.stop_compatible(socket.assigns.current_scope.actor, id)
          {:noreply, playback_failed(socket)}
        end

      _ ->
        {:noreply, playback_failed(socket)}
    end
  end

  defp resume_expired(socket, session, position) do
    case parse_position(position) do
      {offset, ""}
      when offset >= 0 and (is_nil(session.duration_ms) or offset <= session.duration_ms) ->
        actor = socket.assigns.current_scope.actor
        movie_id = socket.assigns.detail.movie.id
        mode = if session.profile == :video, do: :video, else: :auto

        {:noreply,
         Reducer.SelectVersion.start_compatible(
           socket,
           actor,
           movie_id,
           session.file_id,
           offset,
           mode
         )}

      _ ->
        {:noreply, socket}
    end
  end

  defp playback_failed(socket) do
    socket
    |> Phoenix.Component.assign(
      :playback_error,
      "No se pudo preparar esta versión. Vuelve a intentarlo."
    )
    |> Phoenix.Component.assign(:playback_error_reason, "transcode_failed")
  end

  defp parse_id(id) do
    case Integer.parse(id) do
      {value, ""} when value > 0 -> value
      _ -> 0
    end
  end

  defp parse_position(value) when is_binary(value), do: Integer.parse(value)
  defp parse_position(_), do: :error
end
