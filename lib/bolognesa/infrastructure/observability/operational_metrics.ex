defmodule Bolognesa.Infrastructure.Observability.OperationalMetrics do
  @moduledoc "Exports fixed application events without diagnostic identifiers or metadata labels."

  use PromEx.Plugin

  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Infrastructure.Observability.PlaybackEvents

  @impl true
  def event_metrics(_opts) do
    metrics = Enum.flat_map(Events.events() ++ PlaybackEvents.events(), &metrics_for_event/1)
    Event.build(:bolognesa_operational_event_metrics, metrics)
  end

  defp metrics_for_event(event) do
    [
      sum(event ++ [:count], event_name: event, measurement: :count, tags: []),
      distribution(event ++ [:duration_milliseconds],
        event_name: event,
        measurement: :duration_ms,
        tags: [],
        reporter_options: [buckets: duration_buckets(event)]
      )
    ]
  end

  defp duration_buckets([:bolognesa, :playback, :session, _outcome]),
    do: [1_000, 5_000, 15_000, 60_000, 300_000, 900_000, 3_600_000, 10_800_000]

  defp duration_buckets([:bolognesa, :libraries, :scan, _outcome]),
    do: [10, 100, 500, 1_000, 5_000, 15_000, 60_000, 300_000, 900_000, 3_600_000]

  defp duration_buckets(_event),
    do: [1, 5, 10, 25, 50, 100, 250, 500, 1_000, 5_000, 15_000, 60_000, 300_000]
end
