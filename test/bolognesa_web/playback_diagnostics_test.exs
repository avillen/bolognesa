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

    controls =
      Map.merge(params, %{
        "diagnostic" => "controls",
        "controls_group_width" => 500,
        "controls_slider_width" => 400,
        "controls_track_width" => 380,
        "controls_labels" => 2,
        "controls_hidden" => false,
        "css_container" => true,
        "css_layer" => true,
        "intl_units" => false,
        "unicode_properties" => false,
        "browser_major" => 63,
        "intl_unit_constructor" => "ok",
        "intl_unit_format" => "range",
        "time_format_step" => "hour_long",
        "time_format_error" => "range",
        "time_format_locale" => "es"
      })

    assert {:noreply, _} = PlaybackEvents.handle_event("playback_diagnostic", controls, socket)

    assert_receive {^event, %{count: 1},
                    %{
                      diagnostic: :controls,
                      controls_slider_width: 400,
                      controls_labels: 2,
                      browser_major: 63,
                      time_format_step: "hour_long",
                      time_format_error: "range",
                      intl_units: false
                    }}

    for {key, value} <- [
          {"controls_group_width", -1},
          {"controls_slider_width", 100_001},
          {"controls_track_width", "private"},
          {"controls_labels", 3},
          {"css_container", "private"},
          {"browser_major", 1000},
          {"controls_hidden", nil},
          {"intl_unit_format", "private"},
          {"time_format_step", "private"},
          {"time_format_error", "private"},
          {"time_format_locale", "private"}
        ] do
      assert {:noreply, ^socket} =
               PlaybackEvents.handle_event(
                 "playback_diagnostic",
                 Map.put(controls, key, value),
                 socket
               )
    end

    refute_receive {^event, _, _}

    page = Ecto.UUID.generate()

    lifecycle =
      Map.merge(params, %{
        "diagnostic" => "socket_closed",
        "page_id" => page,
        "replayed" => true,
        "session_id" => nil,
        "ws_code" => 1006,
        "ws_clean" => false,
        "ready_state" => 4,
        "network_state" => 2,
        "online" => true,
        "navigation_type" => "reload"
      })

    assert {:noreply, _} = PlaybackEvents.handle_event("playback_diagnostic", lifecycle, socket)
    assert_receive {^event, %{count: 1}, %{page_id: ^page, replayed: true, ws_code: 1006}}

    for invalid <- [
          Map.put(params, "session_id", Ecto.UUID.generate()),
          Map.put(params, "file_id", "4"),
          Map.put(params, "diagnostic", "injected"),
          Map.put(params, "position_ms", -1),
          Map.put(params, "tab_id", "private text"),
          Map.put(params, "media_error", 99),
          Map.put(stall, "buffered_ms", -1),
          Map.put(stall, "stall_duration_ms", "private text"),
          Map.put(lifecycle, "page_id", "private text"),
          Map.put(lifecycle, "ws_code", 99_999),
          Map.put(lifecycle, "navigation_type", "private text")
        ] do
      assert {:noreply, ^socket} =
               PlaybackEvents.handle_event("playback_diagnostic", invalid, socket)
    end

    refute_receive {^event, _, _}

    capped = %{socket | assigns: Map.put(socket.assigns, :playback_diagnostic_count, 120)}
    progress = Map.put(params, "diagnostic", "progress")

    assert {:noreply, sampled} =
             PlaybackEvents.handle_event("playback_diagnostic", progress, capped)

    assert_receive {^event, %{count: 1}, %{diagnostic: :progress}}

    assert {:noreply, ^sampled} =
             PlaybackEvents.handle_event("playback_diagnostic", progress, sampled)

    refute_receive {^event, _, _}

    historical_progress = Map.put(lifecycle, "diagnostic", "progress")

    assert {:noreply, replay1} =
             PlaybackEvents.handle_event("playback_diagnostic", historical_progress, sampled)

    assert_receive {^event, %{count: 1}, %{diagnostic: :progress, replayed: true}}

    assert {:noreply, _} =
             PlaybackEvents.handle_event("playback_diagnostic", historical_progress, replay1)

    assert_receive {^event, %{count: 1}, %{diagnostic: :progress, replayed: true}}

    assert {:noreply, ^capped} =
             PlaybackEvents.handle_event("playback_diagnostic", params, capped)

    refute_receive {^event, _, _}
  end

  test "a stale recovery seek receives an explicit refusal" do
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, transcode_session: nil}}

    assert {:reply, %{accepted: false}, ^socket} =
             PlaybackEvents.handle_event(
               "playback_restore",
               %{
                 "session_id" => Ecto.UUID.generate(),
                 "position_ms" => "400000",
                 "playing" => "true"
               },
               socket
             )
  end

  test "recovery does not report success for a different active session" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        transcode_session: %{
          id: Ecto.UUID.generate(),
          duration_ms: nil
        }
      }
    }

    assert {:reply, %{accepted: false}, ^socket} =
             PlaybackEvents.handle_event(
               "playback_restore",
               %{
                 "session_id" => Ecto.UUID.generate(),
                 "position_ms" => "400000",
                 "playing" => "true"
               },
               socket
             )
  end

  @spec handle_telemetry([atom()], map(), map(), pid()) :: any()
  def handle_telemetry(event, measurements, metadata, caller),
    do: send(caller, {event, measurements, metadata})
end
