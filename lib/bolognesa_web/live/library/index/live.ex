defmodule BolognesaWeb.Library.Index.Live do
  use BolognesaWeb, :live_view
  alias BolognesaWeb.Library.Index.Reducers

  @impl true
  def mount(_params, _session, socket), do: {:ok, Reducers.Initialize.call(socket)}

  @impl true
  def handle_event("validate", %{"library" => params}, socket),
    do: {:noreply, Reducers.Validate.call(socket, params)}

  def handle_event("save", %{"library" => params}, socket),
    do: {:noreply, Reducers.Save.call(socket, params)}

  def handle_event("scan", %{"library_id" => id}, socket),
    do: {:noreply, Reducers.StartScan.call(socket, id)}

  def handle_event("prepare_reinspect", %{"library_id" => id}, socket),
    do: {:noreply, Reducers.Reinspect.prepare(socket, id)}

  def handle_event("cancel_reinspect", _params, socket),
    do: {:noreply, Reducers.Reinspect.cancel(socket)}

  def handle_event("confirm_reinspect", %{"library_id" => id}, socket),
    do: {:noreply, Reducers.Reinspect.confirm(socket, id)}

  @impl true
  def handle_info(:refresh_scan_statuses, socket),
    do: {:noreply, Reducers.FetchScanStatuses.call(socket)}

  @impl true
  def handle_async({:scan_statuses, request_id}, result, socket),
    do: {:noreply, Reducers.ApplyScanStatuses.call(socket, request_id, result)}
end
