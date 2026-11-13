defmodule BolognesaWeb.Library.Index.Live do
  @moduledoc false
  use BolognesaWeb, :live_view

  alias BolognesaWeb.Library.Index.Components.LibraryForm
  alias BolognesaWeb.Library.Index.Components.LibraryList
  alias BolognesaWeb.Library.Index.Components.ReinspectConfirmation
  alias BolognesaWeb.Library.Index.Reducer.ApplyScanStatuses
  alias BolognesaWeb.Library.Index.Reducer.FetchScanStatuses
  alias BolognesaWeb.Library.Index.Reducer.Initialize
  alias BolognesaWeb.Library.Index.Reducer.Reinspect
  alias BolognesaWeb.Library.Index.Reducer.Save
  alias BolognesaWeb.Library.Index.Reducer.StartScan
  alias BolognesaWeb.Library.Index.Reducer.Validate

  @impl true
  def mount(_params, _session, socket), do: {:ok, Initialize.call(socket)}

  @impl true
  def handle_event("open_library_form", _params, socket),
    do: {:noreply, assign(socket, :show_library_form?, true)}

  def handle_event("close_library_form", _params, socket),
    do: {:noreply, socket |> assign(:show_library_form?, false) |> assign(:form_error, nil)}

  def handle_event("validate", %{"library" => params}, socket),
    do: {:noreply, Validate.call(socket, params)}

  def handle_event("save", %{"library" => params}, socket),
    do: {:noreply, Save.call(socket, params)}

  def handle_event("scan", %{"library_id" => id}, socket),
    do: {:noreply, StartScan.call(socket, id)}

  def handle_event("prepare_reinspect", %{"library_id" => id}, socket),
    do: {:noreply, Reinspect.call(socket, :prepare, id)}

  def handle_event("cancel_reinspect", _params, socket),
    do: {:noreply, Reinspect.call(socket, :cancel)}

  def handle_event("confirm_reinspect", %{"library_id" => id}, socket),
    do: {:noreply, Reinspect.call(socket, :confirm, id)}

  @impl true
  def handle_info({:library_status_changed, _library_id}, socket),
    do: {:noreply, FetchScanStatuses.call(socket)}

  @impl true
  def handle_async({:scan_statuses, request_id}, result, socket),
    do: {:noreply, ApplyScanStatuses.call(socket, request_id, result)}
end
