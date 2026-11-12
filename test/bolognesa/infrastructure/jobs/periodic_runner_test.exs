defmodule Bolognesa.Infrastructure.Jobs.PeriodicRunnerTest do
  use ExUnit.Case, async: true

  alias Bolognesa.Infrastructure.Jobs.PeriodicRunner

  test "runs on startup and schedules only after the current run finishes" do
    owner = self()

    run = fn ->
      send(owner, {:running, self()})

      receive do
        :continue -> :ok
      end
    end

    pid = start_supervised!({PeriodicRunner, name: nil, interval_ms: 10, run: run})
    assert_receive {:running, ^pid}
    refute_receive {:running, ^pid}, 30
    send(pid, :continue)
    assert_receive {:running, ^pid}
    send(pid, :continue)
  end
end
