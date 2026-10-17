defmodule BolognesaWeb.Movie.Show.Reducer.ApplyResult do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [stream: 4]

  @spec call(Phoenix.LiveView.Socket.t(), reference(), term()) :: Phoenix.LiveView.Socket.t()
  def call(socket, request_id, result) do
    if socket.assigns.request_id == request_id,
      do: apply_result(socket, result),
      else: socket
  end

  defp apply_result(socket, {:ok, {:ok, detail}}) do
    socket
    |> assign(:loading?, false)
    |> assign(:detail, detail)
    |> stream(:versions, detail.versions, reset: true)
  end

  defp apply_result(socket, {:ok, {:error, :too_many_versions}}),
    do:
      socket
      |> assign(:loading?, false)
      |> assign(:error, gettext("Esta ficha supera el límite de 100 elementos."))

  defp apply_result(socket, _),
    do:
      socket |> assign(:loading?, false) |> assign(:error, gettext("No se encontró la película."))
end
