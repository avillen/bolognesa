defmodule BolognesaWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  alias Bolognesa.Infrastructure.Observability.Events

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://telemetry-metrics.hexdocs.pm
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @spec metrics() :: [Telemetry.Metrics.t()]
  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("bolognesa.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("bolognesa.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("bolognesa.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("bolognesa.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("bolognesa.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # Playback: IDs belong in diagnostic logs, never metric tags.
      sum("bolognesa.playback.session.started.count", tags: [:strategy]),
      sum("bolognesa.playback.session.closed.count", tags: [:reason, :strategy]),
      summary("bolognesa.playback.session.closed.duration_ms",
        tags: [:reason],
        unit: :millisecond
      ),
      sum("bolognesa.playback.hls.failed.count", tags: [:failure_stage, :reason, :resource_type]),
      sum("bolognesa.playback.browser.diagnostic.count", tags: [:diagnostic]),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ] ++ operational_metrics()
  end

  defp operational_metrics do
    Enum.flat_map(Events.events(), fn event ->
      [
        sum(event ++ [:count],
          tags: [:reason, :operation, :result, :failure_stage, :resource_type]
        ),
        summary(event ++ [:duration_ms], unit: :millisecond, tags: [:reason, :operation])
      ]
    end)
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {BolognesaWeb, :count_users, []}
    ]
  end
end
