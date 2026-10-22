defmodule Bolognesa.Infrastructure.OperationalEventsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Bolognesa.Infrastructure.Observability.Events

  setup do
    id = {__MODULE__, make_ref()}
    event = [:bolognesa, :libraries, :scan, :completed]
    :ok = :telemetry.attach(id, event, &__MODULE__.capture/4, self())
    on_exit(fn -> :telemetry.detach(id) end)
    %{event: event}
  end

  @spec capture([atom()], map(), map(), pid()) :: :ok
  def capture(event, measurements, metadata, receiver) do
    send(receiver, {event, measurements, metadata})
    :ok
  end

  test "all subscribers receive only bounded diagnostic fields", %{event: event} do
    assert :ok =
             Events.emit(
               :libraries,
               :scan,
               :completed,
               %{
                 scan_id: 12,
                 job_id: 34,
                 attempt: 2,
                 reason: "/private",
                 token: "secret",
                 library_id: "private@example.com",
                 file_id: -1,
                 result: :completed
               },
               %{duration_ms: 25, files_discovered: 7, count: 999, path: "/secret"}
             )

    assert_receive {^event, %{count: 1, duration_ms: 25, files_discovered: 7}, metadata}
    assert metadata == %{scan_id: 12, job_id: 34, attempt: 2, result: :completed}
  end

  test "invalid enum values and measurements never enter telemetry", %{event: event} do
    Events.emit(
      :libraries,
      :scan,
      :completed,
      %{reason: %{password: "secret"}, result: :not_a_supported_result, job_id: 1.5},
      %{duration_ms: -1, files_discovered: "secret", recovered_count: :infinity}
    )

    assert_receive {^event, %{count: 1}, %{}}
    assert :ok = Events.emit(:unknown, :scan, :completed, %{scan_id: 1})
    assert :ok = Events.emit(:libraries, :scan, "private", %{})
    refute_receive {_, _, _}
  end

  test "one operational observation produces one log with configured formatter fields" do
    previous = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous) end)

    log =
      capture_log(fn ->
        Events.emit(:libraries, :scan, :completed, %{scan_id: 12, job_id: 34, attempt: 2}, %{
          duration_ms: 25,
          files_discovered: 7
        })
      end)

    assert log =~ "scan_id=12"
    assert log =~ "job_id=34"
    assert log =~ "duration_ms=25"
    assert log =~ "files_discovered=7"
    assert length(Regex.scan(~r/Bolognesa operational observation/, log)) == 1
  end

  test "catalogue metrics never tag diagnostic identifiers" do
    events = Events.events()
    metrics = BolognesaWeb.Telemetry.metrics()

    for event <- events do
      assert Enum.any?(metrics, &(&1.event_name == event and &1.measurement == :count))
    end

    for metric <- metrics, metric.event_name in events do
      assert metric.tags -- [:reason, :operation, :result, :failure_stage, :resource_type] == []
    end
  end

  test "operational logs do not inherit unvalidated formatter fields from the emitting process" do
    previous = Logger.metadata()
    on_exit(fn -> Logger.reset_metadata(previous) end)

    Logger.metadata(
      reason: "/private/secret",
      session_id: "private-session-token",
      request_id: "https://private.example/secret",
      user_id: "private@example.com"
    )

    log =
      capture_log(fn ->
        Events.emit(:libraries, :scan, :failed, %{scan_id: 91})

        :telemetry.execute([:bolognesa, :playback, :hls, :failed], %{count: 1}, %{
          reason: :not_found,
          resource_type: :segment,
          status: 404
        })
      end)

    assert log =~ "scan_id=91"
    refute log =~ "private"
    refute log =~ "secret"
  end

  test "elapsed measurements use nonnegative monotonic milliseconds" do
    started = Events.started_at()
    assert is_integer(started)
    assert Events.elapsed(started) >= 0
  end
end
