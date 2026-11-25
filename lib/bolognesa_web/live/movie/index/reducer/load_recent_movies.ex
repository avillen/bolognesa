defmodule BolognesaWeb.Movie.Index.Reducer.LoadRecentMovies do
  @moduledoc "Loads the account's recently watched movies independently of the catalog."
  import Phoenix.LiveView, only: [start_async: 3]
  alias Bolognesa.Movies

  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(socket) do
    actor = socket.assigns.current_scope.actor
    library_id = socket.assigns.active_library_id

    start_async(socket, :recent_movies, fn -> Movies.list_recent_movies(actor, library_id) end)
  end
end
