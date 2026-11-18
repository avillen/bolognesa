defmodule BolognesaWeb.LiveSupport.PlaybackEventsTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  require Logger
  import Bolognesa.TranscodeFixtures
  alias Bolognesa.Playback.Infrastructure.TranscodeManager
  alias BolognesaWeb.LiveSupport.PlaybackAttempt
  alias BolognesaWeb.LiveSupport.PlaybackEvents
  alias Phoenix.LiveView.Logger, as: LiveViewLogger

  test "malformed top-level capability payloads leave checking playback unchanged" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        loading?: false,
        playback: %PlaybackAttempt{phase: :checking, probe: %{generation: "current-generation"}}
      }
    }

    for payload <- [[], "invalid", 42, true, nil] do
      assert {:noreply, ^socket} =
               PlaybackEvents.handle_event("playback_capabilities", payload, socket)
    end
  end

  describe "effects reach the playback facade and their results re-enter the attempt" do
    defp refused(playback, assigns \\ %{}) do
      %Phoenix.LiveView.Socket{
        assigns:
          Map.merge(
            %{
              __changed__: %{},
              loading?: false,
              current_scope: %{actor: nil},
              content_ref: {:movie, 1},
              playback: playback
            },
            assigns
          )
      }
    end

    defp assert_refused(socket),
      do: assert(socket.assigns.playback.error == {:preparation, :forbidden})

    test "selecting a version loads its candidates" do
      socket =
        refused(PlaybackAttempt.new(), %{
          detail: %{versions: [%{id: 3, availability: :available}]}
        })

      assert_refused(PlaybackEvents.select_version(socket, 3))
    end

    test "a capability report selects a plan" do
      playback = %PlaybackAttempt{
        file_id: 3,
        phase: :checking,
        probe: %{generation: "g", candidates: []}
      }

      assert {:noreply, next} =
               PlaybackEvents.handle_event(
                 "playback_capabilities",
                 %{"generation" => "g"},
                 refused(playback)
               )

      assert_refused(next)
    end

    test "a seek delivers the stream again" do
      playback = %PlaybackAttempt{
        file_id: 3,
        phase: :ready,
        session: %{id: "s1", duration_ms: nil, file_id: 3}
      }

      assert {:noreply, next} =
               PlaybackEvents.handle_event(
                 "playback_seek",
                 %{"session_id" => "s1", "position_ms" => "10"},
                 refused(playback)
               )

      assert_refused(next)
    end

    test "the original file and an inspection refresh are prepared through the facade" do
      playback = %PlaybackAttempt{file_id: 3, phase: :error}

      for event <- ["playback_original", "playback_refresh"] do
        assert {:noreply, next} = PlaybackEvents.handle_event(event, %{}, refused(playback))
        assert_refused(next)
      end
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

  describe "with a running conversion" do
    setup :transcode_source

    test "an ended event and LiveView termination retain distinct close causes", %{source: source} do
      attach_lifecycle()

      for {action, expected} <- [{:ended, :ended}, {:terminate, :liveview_terminated}] do
        {:ok, session} =
          TranscodeManager.start(1, {:movie, 2}, 3, source, plan(source, :full_conversion), 0)

        socket = %Phoenix.LiveView.Socket{
          assigns: %{
            __changed__: %{},
            current_scope: %{actor: %{id: 1}},
            playback: %PlaybackAttempt{session: session}
          }
        }

        case action do
          :ended ->
            PlaybackEvents.handle_event("playback_ended", %{"session_id" => session.id}, socket)

          :terminate ->
            PlaybackEvents.terminate({:shutdown, :closed}, socket)
        end

        assert_receive {[:bolognesa, :playback, :session, :closed], _, %{reason: ^expected}}
      end
    end

    test "preparation allows a slow start beyond thirty seconds and stops at sixty", %{
      source: source
    } do
      {:ok, session} =
        TranscodeManager.start(1, {:movie, 2}, 3, source, plan(source, :audio_conversion), 0)

      now = System.monotonic_time(:millisecond)

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          current_scope: %{actor: %{id: 1}},
          playback: %PlaybackAttempt{phase: :preparing, session: session, deadline: now + 15_000}
        }
      }

      assert {:noreply, waiting} =
               PlaybackEvents.handle_info({:transcode_poll, session.id}, socket)

      assert waiting.assigns.playback.phase == :preparing
      assert {:ok, _} = TranscodeManager.lookup(session.id)
      assert_receive {:transcode_poll, id}
      assert id == session.id

      expired = put_in(waiting.assigns.playback.deadline, now - 1)

      assert {:noreply, failed} =
               PlaybackEvents.handle_info({:transcode_poll, session.id}, expired)

      assert failed.assigns.playback.phase == :error
      assert {:error, :not_found} = TranscodeManager.lookup(session.id)
    end

    test "the ended event releases the displayed session", %{source: source} do
      assert {:ok, session} =
               TranscodeManager.start(
                 1,
                 {:movie, 2},
                 3,
                 source,
                 plan(source, :full_conversion),
                 0
               )

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          current_scope: %{actor: %{id: 1}},
          playback: %PlaybackAttempt{session: session}
        }
      }

      assert {:noreply, next} =
               PlaybackEvents.handle_event(
                 "playback_ended",
                 %{"session_id" => session.id},
                 socket
               )

      assert next.assigns.playback.paused?
      assert {:error, :not_found} = TranscodeManager.lookup(session.id)
    end
  end
end
