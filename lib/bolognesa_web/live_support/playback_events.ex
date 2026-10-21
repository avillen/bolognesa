defmodule BolognesaWeb.LiveSupport.PlaybackEvents do
  @moduledoc "Shared LiveView lifecycle for authorized direct and HLS playback."
  alias Bolognesa.Infrastructure.Observability
  alias Bolognesa.Playback
  alias BolognesaWeb.LiveSupport.PlaybackControl
  alias BolognesaWeb.LiveSupport.PlaybackDiagnostics
  alias BolognesaWeb.LiveSupport.PlaybackState
  alias BolognesaWeb.LiveSupport.SelectVersion

  @spec handle_event(binary(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("playback_diagnostic", params, socket),
    do: {:noreply, PlaybackDiagnostics.record(socket, params)}

  def handle_event("play", %{"file_id" => file_id}, socket) do
    {:noreply, SelectVersion.call(socket, file_id)}
  end

  def handle_event("playback_error", %{"file_id" => file_id} = params, socket) do
    if socket.assigns.selected_file_id &&
         Integer.to_string(socket.assigns.selected_file_id) == file_id &&
         is_nil(socket.assigns.compatible_session) && is_nil(socket.assigns.playback_error) do
      {:noreply,
       PlaybackControl.start_compatible(
         socket,
         socket.assigns.selected_file_id,
         fallback_position(params["position_ms"]),
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
        PlaybackControl.stop_previous(socket, :seek)

        next =
          PlaybackControl.start_compatible(
            socket,
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
        Playback.pause_video_compatible(socket.assigns.current_scope.actor, id)
        {:noreply, PlaybackState.paused(socket, true)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("playback_resume", %{"session_id" => id, "position_ms" => position}, socket) do
    case socket.assigns.compatible_session do
      %{id: ^id} = session ->
        resume_session(socket, session, position)

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("playback_ended", %{"file_id" => _id}, socket), do: {:noreply, socket}

  def handle_event("playback_ended", %{"session_id" => id}, socket) do
    case socket.assigns.compatible_session do
      %{id: ^id} ->
        PlaybackControl.stop_previous(socket, :ended)
        {:noreply, PlaybackState.paused(socket, true)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("compatible_error", %{"session_id" => id}, socket) do
    case socket.assigns.compatible_session do
      %{id: ^id} ->
        PlaybackControl.stop_previous(socket, :client_error)

        {:noreply, PlaybackState.conversion_failed(socket, :interrupted)}

      _ ->
        {:noreply, socket}
    end
  end

  @spec handle_info({:compatible_poll, binary()}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:compatible_poll, id}, socket) do
    case socket.assigns.compatible_session do
      %{id: ^id} -> poll_compatible(socket, id)
      _ -> {:noreply, socket}
    end
  end

  @spec terminate(term(), Phoenix.LiveView.Socket.t()) :: :ok
  def terminate(reason, socket) do
    session = socket.assigns[:compatible_session]

    :telemetry.execute([:bolognesa, :playback, :liveview, :terminated], %{count: 1}, %{
      session_id: session && session.id,
      file_id: socket.assigns[:selected_file_id],
      termination_reason: Observability.exit_reason(reason)
    })

    if session, do: PlaybackControl.stop_previous(socket, :liveview_terminated)
    :ok
  end

  defp poll_compatible(socket, id) do
    case Playback.video_compatible_status(id) do
      :ready ->
        Playback.pause_video_compatible(socket.assigns.current_scope.actor, id)

        {:noreply, PlaybackState.ready(socket)}

      :waiting when socket.assigns.compatible_poll_attempts < 60 ->
        Process.send_after(self(), {:compatible_poll, id}, 500)

        {:noreply,
         Phoenix.Component.assign(
           socket,
           :compatible_poll_attempts,
           socket.assigns.compatible_poll_attempts + 1
         )}

      :waiting ->
        PlaybackControl.stop_previous(socket, :preparation_timeout)
        {:noreply, PlaybackState.conversion_failed(socket, :preparation)}

      _ ->
        {:noreply, PlaybackState.conversion_failed(socket, :preparation)}
    end
  end

  defp resume_session(socket, session, position) do
    case Playback.resume_video_compatible(socket.assigns.current_scope.actor, session.id) do
      :ok -> {:noreply, PlaybackState.paused(socket, false)}
      _ -> resume_expired(socket, session, position)
    end
  end

  defp resume_expired(socket, session, position) do
    case parse_position(position) do
      {offset, ""}
      when offset >= 0 and (is_nil(session.duration_ms) or offset <= session.duration_ms) ->
        mode = if session.profile == :video, do: :video, else: :auto

        {:noreply,
         PlaybackControl.start_compatible(
           socket,
           session.file_id,
           offset,
           mode
         )}

      _ ->
        {:noreply, socket}
    end
  end

  defp fallback_position(position) do
    case parse_position(position) do
      {offset, ""} when offset >= 0 -> offset
      _ -> 0
    end
  end

  defp parse_position(value) when is_binary(value), do: Integer.parse(value)
  defp parse_position(_), do: :error
end
