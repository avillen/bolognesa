defmodule BolognesaWeb.Movie.Index.Reducer.ApplyResult do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [stream: 4]

  @spec call(Phoenix.LiveView.Socket.t(), reference(), term()) :: Phoenix.LiveView.Socket.t()
  def call(socket, request_id, result) do
    if socket.assigns.request_id == request_id do
      case result do
        {:ok, {:ok, %{items: items, total: total}}} ->
          socket
          |> assign(:loading?, false)
          |> assign(:total, total)
          |> stream(:movies, items, reset: true)

        _ ->
          socket |> assign(:loading?, false) |> assign(:error, "No se pudo cargar el catálogo.")
      end
    else
      socket
    end
  end
end
