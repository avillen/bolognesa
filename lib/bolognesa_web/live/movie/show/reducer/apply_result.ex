defmodule BolognesaWeb.Movie.Show.Reducer.ApplyResult do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [stream: 4]

  @spec call(Phoenix.LiveView.Socket.t(), reference(), term()) :: Phoenix.LiveView.Socket.t()
  def call(socket, request_id, result) do
    if socket.assigns.request_id == request_id do
      case result do
        {:ok, {:ok, detail}} ->
          socket
          |> assign(:loading?, false)
          |> assign(:detail, detail)
          |> stream(:versions, detail.versions, reset: true)

        _ ->
          socket
          |> assign(:loading?, false)
          |> assign(:error, gettext("No se encontró la película."))
      end
    else
      socket
    end
  end
end
