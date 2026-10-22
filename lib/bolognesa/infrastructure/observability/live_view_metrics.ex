defmodule Bolognesa.Infrastructure.Observability.LiveViewMetrics do
  @moduledoc "LiveView callback timings and exceptions with fixed, server-owned labels."

  use PromEx.Plugin

  alias PromEx.Plugins.PhoenixLiveView

  @views %{
    BolognesaWeb.Setup.Live => "accounts",
    BolognesaWeb.Login.Live => "accounts",
    BolognesaWeb.Settings.Live => "accounts",
    BolognesaWeb.Library.Index.Live => "libraries",
    BolognesaWeb.Movie.Index.Live => "movies",
    BolognesaWeb.Movie.Review.Live => "movies",
    BolognesaWeb.Movie.Show.Live => "movies",
    BolognesaWeb.Series.Index.Live => "series",
    BolognesaWeb.Series.Review.Live => "series",
    BolognesaWeb.Series.Season.Live => "series",
    BolognesaWeb.Series.Show.Live => "series",
    BolognesaWeb.Episode.Show.Live => "series",
    BolognesaWeb.Music.Index.Live => "music",
    BolognesaWeb.Home.Live => "global",
    BolognesaWeb.About.Live => "global"
  }

  @impl true
  def event_metrics(opts) do
    [group | _components] = PhoenixLiveView.event_metrics(opts)
    [mount, exception | _events] = group.metrics

    additional =
      for operation <- [:handle_params, :render], metric <- [mount, exception] do
        %{
          metric
          | name: Enum.map(metric.name, &replace_mount(&1, operation)),
            event_name: Enum.map(metric.event_name, &replace_mount(&1, operation)),
            description: "LiveView #{operation} callback duration."
        }
      end

    metrics = Enum.map(group.metrics ++ additional, &bound_metric/1)
    %{group | metrics: metrics}
  end

  defp replace_mount(:mount, operation), do: operation
  defp replace_mount(part, _operation), do: part

  defp bound_metric(metric) do
    options =
      Keyword.put(metric.reporter_options, :buckets, [
        0.1,
        0.5,
        1,
        5,
        10,
        25,
        50,
        100,
        250,
        500,
        1_000,
        5_000
      ])

    %{metric | tags: [:context, :view], tag_values: &labels/1, reporter_options: options}
  end

  defp labels(%{socket: %{view: view}}) when is_map_key(@views, view) do
    %{
      context: Map.fetch!(@views, view),
      view: view |> Atom.to_string() |> String.trim_leading("Elixir.")
    }
  end

  defp labels(_metadata), do: %{context: "global", view: "other"}
end
