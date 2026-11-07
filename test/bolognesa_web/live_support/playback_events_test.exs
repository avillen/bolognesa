defmodule BolognesaWeb.LiveSupport.PlaybackEventsTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  require Logger
  alias BolognesaWeb.LiveSupport.PlaybackEvents
  alias Phoenix.LiveView.Logger, as: LiveViewLogger

  test "a queued preparation poll cannot replace a terminal failure" do
    id = Ecto.UUID.generate()

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        transcode_session: %{id: id},
        transcode_ready?: false,
        playback_phase: :error,
        playback_error: "Terminal failure"
      }
    }

    assert {:noreply, ^socket} = PlaybackEvents.handle_info({:transcode_poll, id}, socket)
  end

  test "malformed top-level capability payloads leave checking playback unchanged" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        loading?: false,
        playback_phase: :checking,
        playback_probe: %{generation: "current-generation"}
      }
    }

    for payload <- [[], "invalid", 42, true, nil] do
      assert {:noreply, ^socket} =
               PlaybackEvents.handle_event("playback_capabilities", payload, socket)
    end
  end

  test "video views never log valid or rejected capability payloads at debug level" do
    level = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: level) end)

    reports = [
      %{
        "generation" => "private-capability-marker",
        "version" => 1,
        "preference" => "auto",
        "results" => [%{"candidate_id" => "c0", "transport" => "file", "support" => "supported"}]
      },
      %{"unexpected" => %{"nested" => "private-capability-marker"}},
      "private-capability-marker"
    ]

    for view <- [BolognesaWeb.Movie.Show.Live, BolognesaWeb.Series.Episode.Live] do
      logs =
        capture_log([level: :debug], fn ->
          Logger.debug("debug-capture-control")

          for params <- reports do
            LiveViewLogger.lv_handle_event_start(
              [:phoenix, :live_view, :handle_event, :start],
              %{system_time: System.system_time()},
              %{
                socket: %Phoenix.LiveView.Socket{view: view},
                event: "playback_capabilities",
                params: params
              },
              %{}
            )
          end
        end)

      assert logs =~ "debug-capture-control"
      refute logs =~ "private-capability-marker"
    end
  end
end
