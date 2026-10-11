defmodule BolognesaWeb.Library.Index.Reducers.Initialize do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3, to_form: 1]
  import Phoenix.LiveView, only: [stream: 4]

  alias Bolognesa.Libraries
  alias Bolognesa.Libraries.Domain.ReadModels.Scans.ScanStatus

  alias BolognesaWeb.Library.Index.Forms.Library
  alias BolognesaWeb.Library.Index.Reducers.FetchScanStatuses
  alias BolognesaWeb.Library.Index.State.Library, as: LibraryState

  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(socket) do
    socket =
      socket
      |> assign(:page_title, "Bibliotecas")
      |> assign(:form, to_form(Library.changeset()))
      |> assign(:error, nil)
      |> assign(:success, nil)
      |> assign(:scan_request_id, make_ref())
      |> assign(:scan_loading?, false)
      |> assign(:scan_timer_ref, nil)
      |> assign(:scan_active_ids, MapSet.new())
      |> assign(:scan_feedback, nil)
      |> assign(:reinspect_library_id, nil)

    case Libraries.list_libraries(socket.assigns.current_scope.actor) do
      {:ok, libraries} ->
        rows = Enum.map(libraries, &LibraryState.from_domain(&1, %ScanStatus{library_id: &1.id}))
        socket |> stream(:libraries, rows, reset: true) |> FetchScanStatuses.call()

      {:error, _} ->
        socket
        |> assign(:error, "No se pudieron cargar las bibliotecas. Recarga para reintentar.")
        |> stream(:libraries, [], reset: true)
    end
  end
end
