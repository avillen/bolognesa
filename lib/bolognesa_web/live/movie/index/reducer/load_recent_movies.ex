defmodule BolognesaWeb.Movie.Index.Reducer.LoadRecentMovies do
  @moduledoc """
  Loads the account's recently watched movies independently of the catalog.

  The shelf ignores query and page, so it reads again only when the library changes
  or the previous read failed.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [cancel_async: 2, start_async: 3]
  alias Bolognesa.Movies

  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(%{assigns: %{recent_scope: {:library, id}, active_library_id: id}} = socket),
    do: socket

  def call(socket) do
    actor = socket.assigns.current_scope.actor
    library_id = socket.assigns.active_library_id

    socket
    |> assign(:recent_movies, [])
    |> assign(:recent_scope, {:library, library_id})
    |> cancel_async(:recent_movies)
    |> start_async(:recent_movies, fn -> Movies.list_recent_movies(actor, library_id) end)
  end
end
