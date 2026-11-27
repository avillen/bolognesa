defmodule BolognesaWeb.Movie.Index.Reducer.RecentMoviesTest do
  use ExUnit.Case, async: true
  alias BolognesaWeb.Movie.Index.Reducer.ApplyRecentMovies
  alias BolognesaWeb.Movie.Index.Reducer.LoadRecentMovies

  # A disconnected socket starts no task, so only the reducers' state decisions run.
  test "a failed shelf read hides the shelf and lets the next load of the same library retry" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        current_scope: %{actor: nil},
        active_library_id: 7,
        recent_movies: [%{id: 1}],
        recent_scope: {:library, 7}
      }
    }

    assert LoadRecentMovies.call(socket) == socket

    for result <- [{:ok, {:error, :unavailable}}, {:exit, :boom}] do
      failed = ApplyRecentMovies.call(socket, result)
      assert failed.assigns.recent_movies == []
      assert failed.assigns.recent_scope == :unloaded
      assert LoadRecentMovies.call(failed).assigns.recent_scope == {:library, 7}
    end
  end
end
