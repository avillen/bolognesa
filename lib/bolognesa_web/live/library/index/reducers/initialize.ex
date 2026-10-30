defmodule BolognesaWeb.Library.Index.Reducers.Initialize do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 3, to_form: 1]
  import Phoenix.LiveView, only: [connected?: 1]

  alias Bolognesa.Libraries
  alias Bolognesa.Libraries.Domain.ReadModels.Scans.ScanStatus

  alias BolognesaWeb.Library.Index.Forms.Library
  alias BolognesaWeb.Library.Index.LibraryRows
  alias BolognesaWeb.Library.Index.Reducers.FetchScanStatuses
  alias BolognesaWeb.Library.Index.State.Library, as: LibraryState

  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(socket) do
    socket =
      socket
      |> assign(:page_title, gettext("Bibliotecas"))
      |> assign(:form, to_form(Library.changeset()))
      |> assign(:show_library_form?, false)
      |> assign(:load_error, nil)
      |> assign(:form_error, nil)
      |> assign(:scan_refresh_error, nil)
      |> assign(:success, nil)
      |> assign(:scan_request_id, make_ref())
      |> assign(:scan_loading?, false)
      |> assign(:scan_refresh_pending?, false)
      |> assign(:scan_feedback, nil)
      |> assign(:reinspect_target, nil)
      |> subscribe_status_updates()

    case Libraries.list_libraries(socket.assigns.current_scope.actor) do
      {:ok, libraries} ->
        rows = Enum.map(libraries, &LibraryState.from_domain(&1, %ScanStatus{library_id: &1.id}))

        socket
        |> LibraryRows.initialize(rows)
        |> FetchScanStatuses.call()

      {:error, _} ->
        socket
        |> assign(
          :load_error,
          gettext("No se pudieron cargar las bibliotecas. Recarga para reintentar.")
        )
        |> LibraryRows.initialize([])
    end
  end

  defp subscribe_status_updates(socket) do
    if connected?(socket), do: subscribe(socket), else: socket
  end

  defp subscribe(socket) do
    case Libraries.subscribe_status_updates(socket.assigns.current_scope.actor) do
      :ok ->
        socket

      {:error, _reason} ->
        assign(
          socket,
          :scan_feedback,
          gettext("No se pudieron cargar las bibliotecas. Recarga para reintentar.")
        )
    end
  end
end
