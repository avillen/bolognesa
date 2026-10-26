defmodule BolognesaWeb.LiveSupport.PlaybackDiagnostics do
  @moduledoc "Validate bounded, untrusted browser observations without affecting playback."
  import Phoenix.Component, only: [assign: 3]

  @diagnostics %{
    "mounted" => :mounted,
    "disconnected" => :disconnected,
    "reconnected" => :reconnected,
    "visibility" => :visibility,
    "error" => :error,
    "waiting" => :waiting,
    "recovered" => :recovered,
    "pagehide" => :pagehide,
    "pageshow" => :pageshow,
    "online" => :online,
    "offline" => :offline,
    "socket_open" => :socket_open,
    "socket_closed" => :socket_closed,
    "socket_error" => :socket_error,
    "destroyed" => :destroyed,
    "progress" => :progress,
    "restored" => :restored,
    "restore_failed" => :restore_failed,
    "autoplay_blocked" => :autoplay_blocked
  }

  @spec record(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def record(socket, params) do
    with {:ok, metadata} <- validate(socket, params),
         {:ok, next} <- admit(socket, metadata) do
      :telemetry.execute([:bolognesa, :playback, :browser, :diagnostic], %{count: 1}, metadata)
      next
    else
      _ -> socket
    end
  end

  defp admit(socket, %{replayed: true}) do
    count = socket.assigns[:playback_replay_count] || 0
    if count < 8, do: {:ok, assign(socket, :playback_replay_count, count + 1)}, else: :error
  end

  defp admit(socket, %{diagnostic: :progress}) do
    count = socket.assigns[:playback_progress_count] || 0
    now = System.monotonic_time(:millisecond)
    last = socket.assigns[:playback_progress_at]

    if count < 1440 and (is_nil(last) or now - last >= 25_000) do
      {:ok,
       socket |> assign(:playback_progress_count, count + 1) |> assign(:playback_progress_at, now)}
    else
      :error
    end
  end

  defp admit(socket, _metadata) do
    count = socket.assigns[:playback_diagnostic_count] || 0
    if count < 120, do: {:ok, assign(socket, :playback_diagnostic_count, count + 1)}, else: :error
  end

  defp validate(socket, params) do
    session = socket.assigns[:transcode_session]
    expected_session = session && session.id
    file_id = socket.assigns[:selected_file_id]

    with true <- is_integer(file_id) and params["file_id"] == Integer.to_string(file_id),
         {:ok, extra} <- extra_fields(params),
         true <- valid_session?(params["session_id"], expected_session, extra),
         {:ok, tab_id} <- Ecto.UUID.cast(params["tab_id"]),
         {:ok, diagnostic} <- Map.fetch(@diagnostics, params["diagnostic"]),
         position when is_integer(position) and position >= 0 and position <= 2_147_483_647 <-
           params["position_ms"],
         {:ok, buffered, stall_duration} <- buffer_observation(params),
         sequence when is_integer(sequence) and sequence in 1..1_000_000 <- params["sequence"],
         client_time when is_integer(client_time) and client_time in 1..10_000_000_000_000 <-
           params["client_time_ms"],
         paused when is_boolean(paused) <- params["paused"],
         visibility when visibility in ["visible", "hidden"] <- params["visibility"],
         error when is_integer(error) and error in 0..4 <- params["media_error"] do
      {:ok,
       Map.merge(extra, %{
         session_id: params["session_id"],
         file_id: file_id,
         tab_id: tab_id,
         diagnostic: diagnostic,
         position_ms: position,
         buffered_ms: buffered,
         stall_duration_ms: stall_duration,
         sequence: sequence,
         client_time_ms: client_time,
         paused: paused,
         visibility: visibility,
         media_error: error
       })}
    else
      _ -> :error
    end
  end

  defp valid_session?(session, expected, %{replayed: false}), do: session == expected

  defp valid_session?(session, _expected, %{replayed: true, page_id: page_id})
       when not is_nil(page_id),
       do: is_nil(session) or match?({:ok, _}, Ecto.UUID.cast(session))

  defp valid_session?(_session, _expected, _extra), do: false

  defp extra_fields(params) do
    defaults = %{
      page_id: nil,
      replayed: false,
      ws_code: 0,
      ws_clean: false,
      ready_state: 0,
      network_state: 0,
      online: true,
      navigation_type: "unknown"
    }

    fields =
      Map.new(defaults, fn {key, default} ->
        {key, Map.get(params, Atom.to_string(key), default)}
      end)

    if Enum.all?(fields, fn {key, value} -> valid_extra?(key, value) end),
      do: {:ok, fields},
      else: :error
  end

  defp valid_extra?(:page_id, nil), do: true
  defp valid_extra?(:page_id, value), do: match?({:ok, _}, Ecto.UUID.cast(value))
  defp valid_extra?(key, value) when key in [:replayed, :ws_clean, :online], do: is_boolean(value)

  defp valid_extra?(:ws_code, value),
    do: is_integer(value) and (value == 0 or value in 1000..4999)

  defp valid_extra?(:ready_state, value), do: is_integer(value) and value in 0..4
  defp valid_extra?(:network_state, value), do: is_integer(value) and value in 0..3

  defp valid_extra?(:navigation_type, value),
    do: value in ["navigate", "reload", "back_forward", "unknown"]

  defp buffer_observation(params) do
    buffered = Map.get(params, "buffered_ms", 0)
    duration = Map.get(params, "stall_duration_ms", 0)

    if is_integer(buffered) and buffered in 0..2_147_483_647 and
         is_integer(duration) and duration in 0..2_147_483_647 do
      {:ok, buffered, duration}
    else
      :error
    end
  end
end
