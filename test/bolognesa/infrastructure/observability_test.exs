defmodule Bolognesa.Infrastructure.ObservabilityTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  alias Bolognesa.Infrastructure.Observability

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

  test "process exits are reduced to bounded reasons without exception payloads" do
    assert Observability.exit_reason(:normal) == :normal
    assert Observability.exit_reason({:shutdown, :closed}) == :closed
    assert Observability.exit_reason({:shutdown, %{token: "private"}}) == :shutdown
    assert Observability.exit_reason({%RuntimeError{message: "private path"}, []}) == :abnormal
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
end
