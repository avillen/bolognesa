defmodule BolognesaWeb.Series.Show.Reducer.ApplyResult do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [stream: 4]
  alias Bolognesa.Series.Application.UseCases.FetchSeries.Response, as: SeriesDetail

  @type result ::
          {:ok,
           {:ok, SeriesDetail.t()}
           | :not_found
           | {:error, :forbidden | :invalid_page | :unavailable | :too_many_seasons}}
          | {:exit, term()}
  @spec call(Phoenix.LiveView.Socket.t(), reference(), result()) :: Phoenix.LiveView.Socket.t()
  def call(socket, request, result) do
    if socket.assigns.request_id == request, do: apply_result(socket, result), else: socket
  end

  defp apply_result(socket, {:ok, {:ok, detail}}),
    do:
      socket
      |> assign(detail: detail, loading?: false, total: length(detail.seasons))
      |> stream(:seasons, detail.seasons, reset: true)

  defp apply_result(socket, {:ok, {:error, :too_many_seasons}}),
    do:
      assign(socket,
        loading?: false,
        error: gettext("Esta ficha supera el límite de 100 elementos.")
      )

  defp apply_result(socket, _),
    do:
      assign(socket,
        loading?: false,
        error: gettext("No se pudo cargar esta ficha. Vuelve a intentarlo.")
      )
end
