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
        reporter_options: [buckets: [10, 100, 1_000, 10_000, 60_000, 300_000]]
      )
    ]
  end
end
