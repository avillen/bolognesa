defmodule BolognesaWeb.Movie.Index.Reducer.ApplyRecentMovies do
  @moduledoc "Shows the recently watched movies; any failure leaves the shelf hidden."
  import Phoenix.Component, only: [assign: 3]

  @spec call(Phoenix.LiveView.Socket.t(), term()) :: Phoenix.LiveView.Socket.t()
  def call(socket, {:ok, {:ok, recent}}), do: assign(socket, :recent_movies, recent)
  def call(socket, _result), do: assign(socket, :recent_movies, [])
end
