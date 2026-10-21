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
    "recovered" => :recovered
  }

  @spec record(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def record(socket, params) do
    count = socket.assigns[:playback_diagnostic_count] || 0

    with true <- count < 120,
         {:ok, metadata} <- validate(socket, params) do
      :telemetry.execute([:bolognesa, :playback, :browser, :diagnostic], %{count: 1}, metadata)
      assign(socket, :playback_diagnostic_count, count + 1)
    else
      _ -> socket
    end
  end

  defp validate(socket, params) do
    session = socket.assigns[:compatible_session]
    expected_session = session && session.id
    file_id = socket.assigns[:selected_file_id]

    with true <- is_integer(file_id) and params["file_id"] == Integer.to_string(file_id),
         true <- params["session_id"] == expected_session,
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
       %{
         session_id: expected_session,
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
       }}
    else
      _ -> :error
    end
  end

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
