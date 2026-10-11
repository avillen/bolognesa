defmodule BolognesaWeb.Movie.Review.Reducer.ApplyReviewsResult do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [stream: 4]

  @spec call(Phoenix.LiveView.Socket.t(), reference(), term()) :: Phoenix.LiveView.Socket.t()
  def call(socket, request_id, result) do
    if request_id == socket.assigns.request_id do
      case result do
        {:ok, {:ok, %{items: items, total: total}}} ->
          socket
          |> assign(:loading?, false)
          |> assign(:total, total)
          |> stream(:reviews, items, reset: true)

        _ ->
          socket
          |> assign(:loading?, false)
          |> assign(:error, gettext("No se pudo cargar la revisión."))
      end
    else
      socket
    end
  end
end
