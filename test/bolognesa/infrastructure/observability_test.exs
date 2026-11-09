defmodule Bolognesa.Infrastructure.ObservabilityTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  alias Bolognesa.Infrastructure.Observability
  alias Bolognesa.Infrastructure.Observability.Events

  test "playback events are logged once with approved metadata only" do
    previous = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous) end)

    options = [
      level: :info,
      format: "$metadata$message\n",
      metadata: :all
    ]

    log =
      capture_log(options, fn ->
        :telemetry.execute(
          [:bolognesa, :playback, :session, :closed],
          %{count: 1, duration_ms: 42},
          %{
            session_id: "test-session",
            reason: :seek,
            path: "/private/secret",
            token: "secret-token"
          }
        )
      end)

    assert log =~ "session_id=test-session"
    assert log =~ "reason=seek"
    assert log =~ "duration_ms=42"
    assert length(Regex.scan(~r/Playback session closed/, log)) == 1
    refute log =~ "private"
    refute log =~ "secret"
  end

  test "negotiated transport and reason are logged with closed values" do
    previous = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous) end)

    log =
      capture_log([level: :info, format: "$metadata$message\n", metadata: :all], fn ->
        :telemetry.execute([:bolognesa, :playback, :session, :started], %{count: 1}, %{
          strategy: :remux,
          transport: :hls_js,
          delivery_reason: :remux_supported
        })

        :telemetry.execute([:bolognesa, :playback, :session, :started], %{count: 1}, %{
          strategy: "private-strategy",
          transport: "private-uri",
          delivery_reason: "private-reason"
        })
      end)

    assert log =~ "strategy=remux"
    assert log =~ "transport=hls_js"
    assert log =~ "delivery_reason=remux_supported"
    refute log =~ "private"
  end

  test "process exits are reduced to bounded reasons without exception payloads" do
    assert Observability.exit_reason(:normal) == :normal
    assert Observability.exit_reason({:shutdown, :closed}) == :closed
    assert Observability.exit_reason({:shutdown, %{token: "private"}}) == :shutdown
    assert Observability.exit_reason({%RuntimeError{message: "private path"}, []}) == :abnormal
  end

  test "preparation logs include numeric progress but exclude raw tool output" do
    previous = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous) end)

    log =
      capture_log([level: :info, format: "$metadata$message\n", metadata: :all], fn ->
        :telemetry.execute(
          [:bolognesa, :playback, :session, :preparation],
          %{
            duration_ms: 14_000,
            first_progress_ms: 2000,
            progress_age_ms: 500,
            ffmpeg_frame: 240,
            ffmpeg_output_ms: 10_000,
            ffmpeg_speed_milli: 1250,
            stderr: "/private/source.mkv"
          },
          %{stage: :timeout}
        )
      end)

    assert log =~ "first_progress_ms=2000"
    assert log =~ "progress_age_ms=500"
    assert log =~ "ffmpeg_frame=240"
    assert log =~ "ffmpeg_output_ms=10000"
    assert log =~ "ffmpeg_speed_milli=1250"
    refute log =~ "private"
    refute log =~ "stderr"
  end

  test "a supervised restart detaches and reinstalls the handler" do
    old = Process.whereis(Observability)
    ref = Process.monitor(old)
    Supervisor.terminate_child(Bolognesa.Supervisor, Observability)
    assert_receive {:DOWN, ^ref, :process, ^old, _}
    assert {:ok, _} = Supervisor.restart_child(Bolognesa.Supervisor, Observability)

    handlers = :telemetry.list_handlers([:bolognesa, :playback, :session, :closed])
    assert Enum.count(handlers, &(&1.id == Observability)) == 1
  end

  test "startup replaces a handler left behind by an untrappable exit" do
    Supervisor.terminate_child(Bolognesa.Supervisor, Observability)
    on_exit(fn -> Supervisor.restart_child(Bolognesa.Supervisor, Observability) end)

    temporary =
      start_supervised!(%{
        id: :temporary_observation_subscriber,
        start: {GenServer, :start_link, [Observability, [], []]},
        restart: :temporary
      })

    ref = Process.monitor(temporary)
    Process.exit(temporary, :kill)
    assert_receive {:DOWN, ^ref, :process, ^temporary, :killed}

    event = [:bolognesa, :libraries, :scan, :failed]
    assert Enum.any?(:telemetry.list_handlers(event), &(&1.id == Observability))
    assert {:ok, _} = Supervisor.restart_child(Bolognesa.Supervisor, Observability)
    assert Enum.count(:telemetry.list_handlers(event), &(&1.id == Observability)) == 1

    log =
      capture_log(fn ->
        Events.emit(:libraries, :scan, :failed, %{
          scan_id: 51,
          reason: :source_inaccessible
        })
      end)

    assert length(Regex.scan(~r/Bolognesa operational observation/, log)) == 1
  end
end
