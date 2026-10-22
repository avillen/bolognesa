defmodule BolognesaWeb.PlaybackDiagnosticsTest do
  use ExUnit.Case, async: true
  alias BolognesaWeb.LiveSupport.PlaybackEvents

  test "browser observations are bounded and do not change playback" do
    handler = {__MODULE__, make_ref()}
    event = [:bolognesa, :playback, :browser, :diagnostic]
    :ok = :telemetry.attach(handler, event, &__MODULE__.handle_telemetry/4, self())
    on_exit(fn -> :telemetry.detach(handler) end)
    id = Ecto.UUID.generate()
    tab = Ecto.UUID.generate()

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        selected_file_id: 3,
        transcode_session: %{id: id},
        playback_diagnostic_count: 0
      }
    }

    params = %{
      "session_id" => id,
      "file_id" => "3",
      "tab_id" => tab,
      "diagnostic" => "reconnected",
      "position_ms" => 12_000,
      "paused" => false,
      "visibility" => "visible",
      "sequence" => 3,
      "client_time_ms" => 1_790_000_000_000,
      "media_error" => 0,
      "secret" => "never log me"
    }

    assert {:noreply, next} = PlaybackEvents.handle_event("playback_diagnostic", params, socket)
    assert next.assigns.transcode_session == socket.assigns.transcode_session
    assert_receive {^event, %{count: 1}, metadata}
    assert metadata.session_id == id
    assert metadata.tab_id == tab
    assert metadata.diagnostic == :reconnected
    refute Map.has_key?(metadata, :secret)

    stall =
      Map.merge(params, %{
        "diagnostic" => "recovered",
        "buffered_ms" => 8000,
        "stall_duration_ms" => 1600
      })

    assert {:noreply, _} = PlaybackEvents.handle_event("playback_diagnostic", stall, socket)

    assert_receive {^event, %{count: 1},
                    %{diagnostic: :recovered, buffered_ms: 8000, stall_duration_ms: 1600}}

    for invalid <- [
          Map.put(params, "session_id", Ecto.UUID.generate()),
          Map.put(params, "file_id", "4"),
          Map.put(params, "diagnostic", "injected"),
          Map.put(params, "position_ms", -1),
          Map.put(params, "tab_id", "private text"),
          Map.put(params, "media_error", 99),
          Map.put(stall, "buffered_ms", -1),
          Map.put(stall, "stall_duration_ms", "private text")
        ] do
      assert {:noreply, ^socket} =
               PlaybackEvents.handle_event("playback_diagnostic", invalid, socket)
    end

    refute_receive {^event, _, _}
    capped = %{socket | assigns: Map.put(socket.assigns, :playback_diagnostic_count, 120)}

    assert {:noreply, ^capped} =
             PlaybackEvents.handle_event("playback_diagnostic", params, capped)

    refute_receive {^event, _, _}
  end

  @spec handle_telemetry([atom()], map(), map(), pid()) :: any()
  def handle_telemetry(event, measurements, metadata, caller),
    do: send(caller, {event, measurements, metadata})
end
