defmodule BolognesaWeb.Series.Review.Reducer.ApplyReviewsResult do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [stream: 4]
  alias BolognesaWeb.Series.Review.AsyncRequest

  @spec call(Phoenix.LiveView.Socket.t(), reference(), {:ok, term()} | {:exit, term()}) ::
          Phoenix.LiveView.Socket.t()
  def call(socket, ref, result) do
    case AsyncRequest.complete(socket, :reviews, ref) do
      {:ok, socket} -> apply_result(socket, result)
      :stale -> socket
    end
  end

  defp apply_result(socket, {:ok, {:ok, {page, item}}}) do
    socket
    |> assign(loading?: false, error: nil, total: page.total, selected_item: item)
    |> stream(:reviews, page.items, reset: true)
  end

  defp apply_result(socket, _),
    do:
      assign(socket,
        loading?: false,
        error:
          gettext("No se pudo cargar la revisión. Comprueba el archivo y vuelve a intentarlo."),
        selected_item: nil
      )
end
