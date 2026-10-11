defmodule BolognesaWeb.Series.Show.Reducer.Load do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [start_async: 3]
  alias Bolognesa.Catalog
  @spec call(Phoenix.LiveView.Socket.t(), integer(), pos_integer()) :: Phoenix.LiveView.Socket.t()
  def call(socket, id, page) do
    actor = socket.assigns.current_scope.actor
    request = make_ref()

    socket
    |> assign(content_id: id, page: page, request_id: request, loading?: true, error: nil)
    |> start_async({:series_detail, request}, fn -> Catalog.get_series(actor, id) end)
  end
end
