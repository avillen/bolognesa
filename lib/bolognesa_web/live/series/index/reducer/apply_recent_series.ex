defmodule BolognesaWeb.Series.Index.Reducer.ApplyRecentSeries do
  @moduledoc """
  Shows the recently watched series; any failure leaves the shelf hidden and lets the next
  navigation read it again.
  """
  import Phoenix.Component, only: [assign: 3]

  @spec call(Phoenix.LiveView.Socket.t(), term()) :: Phoenix.LiveView.Socket.t()
  def call(socket, {:ok, {:ok, recent}}), do: assign(socket, :recent_series, recent)

  def call(socket, _result),
    do: socket |> assign(:recent_series, []) |> assign(:recent_scope, :unloaded)
end
