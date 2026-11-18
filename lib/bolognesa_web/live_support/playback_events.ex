defmodule BolognesaWeb.LiveSupport.PlaybackEvents do
  @moduledoc """
  Shared LiveView lifecycle for authorized direct and HLS playback.

  Decodes browser events into `PlaybackAttempt` transitions held in the
  `:playback` assign and performs the effects they return.
  """
  alias Bolognesa.Infrastructure.Observability
  alias Bolognesa.Libraries
  alias Bolognesa.Playback
  alias BolognesaWeb.LiveSupport.PlaybackAttempt
  alias BolognesaWeb.LiveSupport.PlaybackDiagnostics
  alias BolognesaWeb.Params
  alias Phoenix.Component

  @type capability_payload :: map() | list() | binary() | number() | boolean() | nil

  @spec handle_event(binary(), capability_payload(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
          | {:reply, map(), Phoenix.LiveView.Socket.t()}
  def handle_event("playback_diagnostic", params, socket),
    do: {:noreply, PlaybackDiagnostics.record(socket, params)}

  def handle_event("play", %{"file_id" => file_id}, socket) do
    case Params.positive_integer(file_id) do
      nil -> {:noreply, socket}
      file_id -> {:noreply, select_version(socket, file_id)}
    end
  end

  def handle_event("play", _params, socket), do: {:noreply, socket}

  def handle_event("playback_restore", %{"session_id" => id, "position_ms" => _} = params, socket) do
    {:noreply, next} = handle_event("playback_seek", params, socket)
    previous = socket.assigns.playback.session
    session = next.assigns.playback.session

    accepted =
      not is_nil(previous) and previous.id == id and not is_nil(session) and
        session.id != previous.id and is_nil(next.assigns.playback.error)

    {:reply, %{accepted: accepted}, next}
  end

  def handle_event("playback_restore", _params, socket),
    do: {:reply, %{accepted: false}, socket}

  def handle_event("playback_capabilities", params, socket) when is_map(params),
    do: {:noreply, unless_loading(socket, &PlaybackAttempt.report(&1, params))}

  def handle_event("playback_capabilities", _params, socket), do: {:noreply, socket}

  def handle_event("playback_compatible", _params, socket),
    do: {:noreply, unless_loading(socket, &PlaybackAttempt.play_compatible/1)}

  def handle_event("playback_original", _params, socket),
    do: {:noreply, transition(socket, &PlaybackAttempt.play_original/1)}

  def handle_event("playback_refresh", _params, socket),
    do: {:noreply, transition(socket, &PlaybackAttempt.refresh/1)}

  def handle_event("playback_error", params, socket),
    do: {:noreply, unless_loading(socket, &PlaybackAttempt.client_failed(&1, :file, params))}

  def handle_event("transcode_error", params, socket),
    do: {:noreply, unless_loading(socket, &PlaybackAttempt.client_failed(&1, :session, params))}

  def handle_event("playback_seek", params, socket),
    do: {:noreply, transition(socket, &PlaybackAttempt.seek(&1, params))}

  def handle_event("playback_pause", %{"session_id" => id}, socket),
    do: {:noreply, transition(socket, &PlaybackAttempt.pause(&1, id))}

  def handle_event("playback_resume", params, socket),
    do: {:noreply, transition(socket, &PlaybackAttempt.resume(&1, params))}

  def handle_event("playback_ended", params, socket),
    do: {:noreply, transition(socket, &PlaybackAttempt.ended(&1, params))}

  @spec handle_info(
          {:transcode_poll | :capability_timeout, binary()},
          Phoenix.LiveView.Socket.t()
        ) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:capability_timeout, generation}, socket),
    do: {:noreply, transition(socket, &PlaybackAttempt.capability_timed_out(&1, generation))}

  def handle_info({:transcode_poll, id}, socket),
    do: {:noreply, transition(socket, &PlaybackAttempt.poll_due(&1, id))}

  @spec terminate(term(), Phoenix.LiveView.Socket.t()) :: :ok
  def terminate(reason, socket) do
    attempt = socket.assigns[:playback] || PlaybackAttempt.new()
    session = attempt.session

    :telemetry.execute([:bolognesa, :playback, :liveview, :terminated], %{count: 1}, %{
      session_id: session && session.id,
      file_id: attempt.file_id,
      termination_reason: Observability.exit_reason(reason)
    })

    if session, do: perform({:stop_session, session.id, :liveview_terminated}, socket)
    :ok
  end

  @doc "Starts a new attempt for one of the loaded detail's available versions."
  @spec select_version(Phoenix.LiveView.Socket.t(), pos_integer()) :: Phoenix.LiveView.Socket.t()
  def select_version(socket, file_id) do
    with %{versions: versions} <- socket.assigns.detail,
         true <- file_id > 0,
         %{availability: :available} <- Enum.find(versions, &(&1.id == file_id)) do
      transition(socket, &PlaybackAttempt.select(&1, file_id))
    else
      _ -> socket
    end
  end

  @doc "Stops any displayed session and starts over with no selected file."
  @spec reset(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def reset(socket), do: transition(socket, &PlaybackAttempt.reset/1)

  @doc "Ends the displayed stream once the browser reports it finished."
  @spec ended(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def ended(socket, session_id),
    do: transition(socket, &PlaybackAttempt.ended(&1, %{"session_id" => session_id}))

  # The screen's loading flag is not part of the attempt.
  defp unless_loading(socket, fun),
    do: if(socket.assigns[:loading?], do: socket, else: transition(socket, fun))

  defp transition(socket, fun) do
    {attempt, effects} = fun.(socket.assigns.playback)
    run(socket, attempt, effects)
  end

  defp run(socket, attempt, effects) do
    socket = if attempt == socket.assigns.playback, do: socket, else: assign(socket, attempt)
    Enum.reduce(effects, socket, &execute/2)
  end

  defp execute(effect, socket) do
    case perform(effect, socket) do
      :ok ->
        socket

      {:result, result} ->
        now = System.monotonic_time(:millisecond)
        {attempt, effects} = PlaybackAttempt.resolve(socket.assigns.playback, effect, result, now)
        run(socket, attempt, effects)
    end
  end

  defp assign(socket, attempt), do: Component.assign(socket, :playback, attempt)

  defp perform({:schedule_capability_timeout, generation, after_ms}, _socket) do
    Process.send_after(self(), {:capability_timeout, generation}, after_ms)
    :ok
  end

  defp perform({:schedule_poll, id, after_ms}, _socket) do
    Process.send_after(self(), {:transcode_poll, id}, after_ms)
    :ok
  end

  defp perform({:stop_session, id, reason}, socket) do
    Playback.stop_video_transcode(actor(socket), id, reason)
    :ok
  end

  defp perform({:load_candidates, file_id}, socket),
    do: {:result, Playback.video_candidates(actor(socket), content_ref(socket), file_id)}

  defp perform({:select_plan, _purpose, file_id, candidates, raw}, socket) do
    {:result,
     Playback.select_video_plan(
       actor(socket),
       content_ref(socket),
       file_id,
       candidates,
       raw,
       raw["generation"]
     )}
  end

  defp perform({:deliver, file_id, plan, offset_ms, reason, _autoplay}, socket) do
    {:result,
     Playback.prepare_video(actor(socket), content_ref(socket), file_id, plan, offset_ms, reason)}
  end

  defp perform({:fetch_status, id}, _socket), do: {:result, Playback.video_transcode_status(id)}

  defp perform({:prepare_original, file_id}, socket),
    do: {:result, Playback.prepare_original(actor(socket), content_ref(socket), file_id)}

  defp perform({:refresh_inspection, file_id}, socket) do
    actor = actor(socket)

    with {:ok, source} <- Playback.start_video(actor, content_ref(socket), file_id),
         {:ok, _} <- Libraries.request_inspection_refresh(actor, file_id, source.revision) do
      {:result, :ok}
    else
      {:error, reason} -> {:result, {:error, reason}}
    end
  end

  defp perform({:resume_session, id, _offset}, socket),
    do: {:result, Playback.resume_video_transcode(actor(socket), id)}

  defp actor(socket), do: socket.assigns.current_scope.actor
  defp content_ref(socket), do: socket.assigns.content_ref
end
