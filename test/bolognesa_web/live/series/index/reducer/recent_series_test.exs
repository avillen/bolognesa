defmodule BolognesaWeb.Series.Index.Reducer.RecentSeriesTest do
  use ExUnit.Case, async: true
  alias BolognesaWeb.Series.Index.Reducer.ApplyRecentSeries
  alias BolognesaWeb.Series.Index.Reducer.LoadRecentSeries

  # A disconnected socket starts no task, so only the reducers' state decisions run.
  test "a failed shelf read hides the shelf and lets the next load of the same library retry" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        current_scope: %{actor: nil},
        active_library_id: 7,
        recent_series: [%{id: 1}],
        recent_scope: {:library, 7}
      }
    }

    assert LoadRecentSeries.call(socket) == socket

    for result <- [{:ok, {:error, :unavailable}}, {:exit, :boom}] do
      failed = ApplyRecentSeries.call(socket, result)
      assert failed.assigns.recent_series == []
      assert failed.assigns.recent_scope == :unloaded
      assert LoadRecentSeries.call(failed).assigns.recent_scope == {:library, 7}
    end
  end
end
