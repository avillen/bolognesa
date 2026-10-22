defmodule Bolognesa.Infrastructure.Observability.PhoenixMetrics do
  @moduledoc "PromEx HTTP metrics with bounded methods and no client-supplied host labels."

  use PromEx.Plugin

  alias PromEx.Plugins.Phoenix

  @methods ~w(GET HEAD POST PUT PATCH DELETE OPTIONS CONNECT TRACE)

  @impl true
  def event_metrics(opts) do
    opts
    |> Phoenix.event_metrics()
    |> Enum.filter(&(&1.group_name in [:phoenix_http_event_metrics, :phoenix_endpoint_metrics]))
    |> Enum.map(&bound_group_labels/1)
  end

  defp bound_group_labels(group) do
    metrics = group.metrics |> Enum.reject(&(:url in &1.tags)) |> Enum.map(&bound_labels/1)
    %{group | metrics: metrics}
  end

  defp bound_labels(metric) do
    tag_values =
      if :method in metric.tags,
        do: bounded_tag_values(metric.tag_values),
        else: metric.tag_values

    %{metric | tags: List.delete(metric.tags, :host), tag_values: tag_values}
  end

  defp bounded_tag_values(tag_values) do
    fn metadata ->
      tags = tag_values.(metadata)
      method = if tags[:method] in @methods, do: tags[:method], else: "OTHER"
      tags |> Map.delete(:host) |> Map.put(:method, method)
    end
  end
end
