defmodule BolognesaWeb.Library.Index.Live do
  @moduledoc false
  use BolognesaWeb, :live_view

  alias BolognesaWeb.Library.Index.Components.LibraryForm
  alias BolognesaWeb.Library.Index.Components.LibraryList
  alias BolognesaWeb.Library.Index.Components.ReinspectConfirmation
  alias BolognesaWeb.Library.Index.Reducer.ApplyScanStatusesCoordinator
  alias BolognesaWeb.Library.Index.Reducer.ConfirmReinspectCoordinator
  alias BolognesaWeb.Library.Index.Reducer.FetchScanStatuses
  alias BolognesaWeb.Library.Index.Reducer.InitializeCoordinator
  alias BolognesaWeb.Library.Index.Reducer.PrepareReinspect
  alias BolognesaWeb.Library.Index.Reducer.SaveCoordinator
  alias BolognesaWeb.Library.Index.Reducer.StartScan
  alias BolognesaWeb.Library.Index.Reducer.Validate

  @impl true
  def mount(_params, _session, socket), do: {:ok, InitializeCoordinator.call(socket)}

  @impl true
  def handle_event("open_library_form", _params, socket),
    do: {:noreply, assign(socket, :show_library_form?, true)}

  def handle_event("close_library_form", _params, socket),
    do: {:noreply, socket |> assign(:show_library_form?, false) |> assign(:form_error, nil)}

  def handle_event("validate", %{"library" => params}, socket),
    do: {:noreply, Validate.call(socket, params)}

  def handle_event("save", %{"library" => params}, socket),
    do: {:noreply, SaveCoordinator.call(socket, params)}

  def handle_event("scan", %{"library_id" => id}, socket),
    do: {:noreply, socket |> StartScan.call(id) |> FetchScanStatuses.call()}

  def handle_event("prepare_reinspect", %{"library_id" => id}, socket),
    do: {:noreply, PrepareReinspect.call(socket, id)}

  def handle_event("cancel_reinspect", _params, socket),
    do: {:noreply, assign(socket, :reinspect_target, nil)}

  def handle_event("confirm_reinspect", %{"library_id" => id}, socket),
    do: {:noreply, ConfirmReinspectCoordinator.call(socket, id)}

  @impl true
  def handle_info({:library_status_changed, _library_id}, socket),
    do: {:noreply, FetchScanStatuses.call(socket)}

  @impl true
  def handle_async({:scan_statuses, request_id}, result, socket),
    do: {:noreply, ApplyScanStatusesCoordinator.call(socket, request_id, result)}
end
