defmodule Bolognesa.Infrastructure.Observability.EctoMetrics do
  @moduledoc "PromEx Ecto metrics with buckets suitable for small local queries."

  use PromEx.Plugin

  alias PromEx.Plugins.Ecto

  @impl true
  def event_metrics(opts) do
    Enum.map(Ecto.event_metrics(opts), &refine_durations/1)
  end

  defp refine_durations(group) do
    metrics = Enum.map(group.metrics, &refine_duration/1) ++ error_metrics(group)
    %{group | metrics: metrics}
  end

  defp error_metrics(%{group_name: :ecto_query_event_metrics, metrics: metrics}) do
    template = Enum.find(metrics, &(:execution in &1.name))

    [
      counter(Enum.drop(template.name, -3) ++ [:errors, :total],
        event_name: template.event_name,
        tags: [:repo, :source],
        tag_values: template.tag_values,
        keep: fn metadata -> match?({:error, _reason}, metadata[:result]) end
      )
    ]
  end

  defp error_metrics(_group), do: []

  defp refine_duration(%Telemetry.Metrics.Distribution{unit: :millisecond} = metric) do
    options =
      Keyword.put(metric.reporter_options, :buckets, [
        0.1,
        0.5,
        1,
        2.5,
        5,
        10,
        25,
        50,
        100,
        500,
        5_000,
        30_000
      ])

    %{metric | reporter_options: options}
  end

  defp refine_duration(metric), do: metric
end
