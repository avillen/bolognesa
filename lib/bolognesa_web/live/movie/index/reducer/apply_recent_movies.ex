defmodule BolognesaWeb.Movie.Index.Reducer.ApplyRecentMovies do
  @moduledoc """
  Shows the recently watched movies; any failure leaves the shelf hidden and lets the next
  navigation read it again.
  """
  import Phoenix.Component, only: [assign: 3]

  @spec call(Phoenix.LiveView.Socket.t(), term()) :: Phoenix.LiveView.Socket.t()
  def call(socket, {:ok, {:ok, recent}}), do: assign(socket, :recent_movies, recent)

  def call(socket, _result),
    do: socket |> assign(:recent_movies, []) |> assign(:recent_scope, :unloaded)
end
