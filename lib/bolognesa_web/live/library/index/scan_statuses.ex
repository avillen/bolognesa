defmodule BolognesaWeb.Library.Index.ScanStatuses do
  @moduledoc "Screen-local helper for the pending scan status request."
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [cancel_async: 2]

  @doc "Cancels the pending status reload so a newer one can start."
  @spec cancel(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def cancel(socket) do
    socket
    |> cancel_async({:scan_statuses, socket.assigns.scan_request_id})
    |> assign(:scan_request_id, make_ref())
    |> assign(:scan_loading?, false)
    |> assign(:scan_refresh_pending?, false)
  end
end
