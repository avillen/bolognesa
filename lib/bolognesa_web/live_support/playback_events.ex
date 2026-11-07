defmodule BolognesaWeb.LiveSupport.PlaybackEvents do
  @moduledoc "Shared LiveView lifecycle for authorized direct and HLS playback."
  alias Bolognesa.Infrastructure.Observability
  alias Bolognesa.Playback
  alias BolognesaWeb.LiveSupport.PlaybackControl
  alias BolognesaWeb.LiveSupport.PlaybackDiagnostics
  alias BolognesaWeb.LiveSupport.PlaybackState

  @spec handle_event(binary(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("playback_diagnostic", params, socket),
    do: {:noreply, PlaybackDiagnostics.record(socket, params)}

  def handle_event("play", %{"file_id" => file_id}, socket) when is_binary(file_id) do
    case Integer.parse(file_id) do
      {file_id, ""} when file_id > 0 ->
        {:noreply, PlaybackControl.select_version(socket, file_id)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("play", _params, socket), do: {:noreply, socket}

  def handle_event("playback_restore", %{"session_id" => id, "position_ms" => _} = params, socket) do
    {:noreply, next} = handle_event("playback_seek", params, socket)
    previous = socket.assigns[:transcode_session]
    session = next.assigns[:transcode_session]

    accepted =
      not is_nil(previous) and previous.id == id and not is_nil(session) and
        session.id != previous.id and is_nil(next.assigns[:playback_error])

    {:reply, %{accepted: accepted}, next}
  end

  def handle_event("playback_restore", _params, socket),
    do: {:reply, %{accepted: false}, socket}

  def handle_event("playback_capabilities", params, socket),
    do: {:noreply, PlaybackControl.accept_report(socket, params)}

  def handle_event("playback_original", _params, socket) do
    if socket.assigns.selected_file_id do
      case Playback.prepare_original(
             socket.assigns.current_scope.actor,
             socket.assigns.content_ref,
             socket.assigns.selected_file_id
           ) do
        {:ok, :direct} ->
          PlaybackControl.stop_transcode(socket, :version_selected)

          {:noreply,
           socket
           |> Phoenix.Component.assign(:playback_attempt_id, Ecto.UUID.generate())
           |> Phoenix.Component.assign(:capability_report, nil)
           |> Phoenix.Component.assign(:recovery_used?, true)
           |> Phoenix.Component.assign(:delivery_plan, nil)
           |> PlaybackState.direct(socket.assigns.selected_file_id)}

        {:error, reason} ->
          {:noreply, PlaybackState.preparation_failed(socket, reason)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("playback_refresh", _params, socket) do
    if socket.assigns.selected_file_id && !socket.assigns.inspection_refresh_used? do
      actor = socket.assigns.current_scope.actor
      socket = Phoenix.Component.assign(socket, :inspection_refresh_used?, true)

      with {:ok, source} <-
             Playback.start_video(
               actor,
               socket.assigns.content_ref,
               socket.assigns.selected_file_id
             ),
           {:ok, _} <-
             Bolognesa.Libraries.request_inspection_refresh(
               actor,
               socket.assigns.selected_file_id,
               source.revision
             ) do
        {:noreply, Phoenix.Component.assign(socket, :inspection_refresh_requested?, true)}
      else
        {:error, reason} -> {:noreply, PlaybackState.preparation_failed(socket, reason)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("playback_error", %{"file_id" => id} = params, socket) do
    if socket.assigns.selected_file_id && to_string(socket.assigns.selected_file_id) == id &&
         is_nil(socket.assigns.transcode_session) do
      client_failure(socket, params)
    else
      {:noreply, socket}
    end
  end

  def handle_event("playback_error", _params, socket), do: {:noreply, socket}

  def handle_event(
        "playback_seek",
        %{"session_id" => id, "position_ms" => position} = params,
        socket
      ) do
    session = socket.assigns.transcode_session

    case parse_position(position) do
      {offset, ""}
      when not is_nil(session) and session.id == id and
             socket.assigns.playback_phase == :ready and offset >= 0 and offset <= 2_147_483_647 and
             (is_nil(session.duration_ms) or offset <= session.duration_ms) ->
        next =
          PlaybackControl.deliver(socket, offset, :seek)

        {:noreply,
         Phoenix.Component.assign(next, :transcode_autoplay?, params["playing"] == "true")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("playback_pause", %{"session_id" => id}, socket) do
    case socket.assigns.transcode_session do
      %{id: ^id} ->
        Playback.pause_video_transcode(socket.assigns.current_scope.actor, id)
        {:noreply, PlaybackState.paused(socket, true)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("playback_resume", %{"session_id" => id, "position_ms" => position}, socket) do
    case socket.assigns.transcode_session do
      %{id: ^id} = session ->
        resume_session(socket, session, position)

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("playback_ended", %{"file_id" => _id}, socket), do: {:noreply, socket}

  def handle_event("playback_ended", %{"session_id" => id}, socket) do
    case socket.assigns.transcode_session do
      %{id: ^id} ->
        PlaybackControl.stop_transcode(socket, :ended)
        {:noreply, PlaybackState.paused(socket, true)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("transcode_error", %{"session_id" => id} = params, socket) do
    case socket.assigns.transcode_session do
      %{id: ^id} -> client_failure(socket, params)
      _ -> {:noreply, socket}
    end
  end

  def handle_event("transcode_error", _params, socket), do: {:noreply, socket}

  @spec handle_info(
          {:transcode_poll | :capability_timeout, binary()},
          Phoenix.LiveView.Socket.t()
        ) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:capability_timeout, generation}, socket) do
    if socket.assigns.playback_phase == :checking &&
         socket.assigns.playback_probe.generation == generation do
      {:noreply, PlaybackState.preparation_failed(socket, :detection_unknown)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:transcode_poll, id}, socket) do
    case {socket.assigns.transcode_session, socket.assigns.transcode_ready?,
          socket.assigns.playback_phase} do
      {%{id: ^id}, false, :preparing} -> poll_transcode(socket, id)
      _ -> {:noreply, socket}
    end
  end

  @spec terminate(term(), Phoenix.LiveView.Socket.t()) :: :ok
  def terminate(reason, socket) do
    session = socket.assigns[:transcode_session]

    :telemetry.execute([:bolognesa, :playback, :liveview, :terminated], %{count: 1}, %{
      session_id: session && session.id,
      file_id: socket.assigns[:selected_file_id],
      termination_reason: Observability.exit_reason(reason)
    })

    if session, do: PlaybackControl.stop_transcode(socket, :liveview_terminated)
    :ok
  end

  defp poll_transcode(socket, id) do
    case Playback.video_transcode_status(id) do
      :ready ->
        Playback.pause_video_transcode(socket.assigns.current_scope.actor, id)

        {:noreply, PlaybackState.ready(socket)}

      :waiting ->
        wait_or_timeout(socket, id)

      _ ->
        {:noreply, PlaybackState.transcode_failed(socket, :preparation)}
    end
  end

  defp wait_or_timeout(socket, id) do
    if System.monotonic_time(:millisecond) < socket.assigns.preparation_deadline do
      Process.send_after(self(), {:transcode_poll, id}, 500)

      {:noreply,
       Phoenix.Component.assign(
         socket,
         :transcode_poll_attempts,
         socket.assigns.transcode_poll_attempts + 1
       )}
    else
      PlaybackControl.stop_transcode(socket, :preparation_timeout)
      {:noreply, PlaybackState.transcode_failed(socket, :preparation)}
    end
  end

  defp resume_session(%{assigns: %{playback_phase: phase}} = socket, _session, _position)
       when phase != :ready, do: {:noreply, socket}

  defp resume_session(socket, session, position) do
    case Playback.resume_video_transcode(socket.assigns.current_scope.actor, session.id) do
      :ok -> {:noreply, PlaybackState.paused(socket, false)}
      _ -> resume_expired(socket, session, position)
    end
  end

  defp resume_expired(socket, session, position) do
    case parse_position(position) do
      {offset, ""}
      when offset >= 0 and offset <= 2_147_483_647 and
             (is_nil(session.duration_ms) or offset <= session.duration_ms) ->
        {:noreply, PlaybackControl.deliver(socket, offset, :session_replaced)}

      _ ->
        {:noreply, socket}
    end
  end

  defp client_failure(socket, params) do
    with true <- socket.assigns.playback_phase == :ready and !socket.assigns[:loading?],
         attempt when is_binary(attempt) <- socket.assigns[:playback_attempt_id],
         ^attempt <- params["attempt_id"],
         {offset, ""} when offset >= 0 and offset <= 2_147_483_647 <-
           parse_position(params["position_ms"]),
         true <- valid_position?(socket, offset) do
      handle_client_failure(socket, params["error_kind"], offset)
    else
      _ -> {:noreply, socket}
    end
  end

  defp handle_client_failure(socket, "media", offset) do
    {:noreply, PlaybackControl.recover(socket, offset)}
  end

  defp handle_client_failure(socket, kind, _offset)
       when kind in ["network", "aborted", "unknown"] do
    PlaybackControl.stop_transcode(socket, :client_error)
    {:noreply, PlaybackState.transcode_failed(socket, :interrupted)}
  end

  defp handle_client_failure(socket, _kind, _offset), do: {:noreply, socket}

  defp valid_position?(socket, offset) do
    duration = socket.assigns[:playback_duration_ms]
    is_nil(duration) or offset <= duration
  end

  defp parse_position(value) when is_binary(value), do: Integer.parse(value)
  defp parse_position(_), do: :error
end
