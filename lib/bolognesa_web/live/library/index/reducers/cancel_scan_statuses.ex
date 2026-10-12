defmodule BolognesaWeb.Library.Index.Reducers.CancelScanStatuses do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [cancel_async: 2]

  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(socket) do
    socket
    |> cancel_async({:scan_statuses, socket.assigns.scan_request_id})
    |> assign(:scan_request_id, make_ref())
    |> assign(:scan_loading?, false)
    |> assign(:scan_refresh_pending?, false)
  end
end
