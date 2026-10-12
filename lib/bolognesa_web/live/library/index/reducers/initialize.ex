defmodule BolognesaWeb.Library.Index.Reducers.Initialize do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 3, to_form: 1]
  import Phoenix.LiveView, only: [stream: 4, connected?: 1]

  alias Bolognesa.Libraries
  alias Bolognesa.Libraries.Domain.ReadModels.Scans.ScanStatus

  alias BolognesaWeb.Library.Index.Forms.Library
  alias BolognesaWeb.Library.Index.Reducers.FetchScanStatuses
  alias BolognesaWeb.Library.Index.State.Library, as: LibraryState

  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(socket) do
    socket =
      socket
      |> assign(:page_title, gettext("Bibliotecas"))
      |> assign(:form, to_form(Library.changeset()))
      |> assign(:error, nil)
      |> assign(:success, nil)
      |> assign(:scan_request_id, make_ref())
      |> assign(:scan_loading?, false)
      |> assign(:scan_refresh_pending?, false)
      |> assign(:scan_feedback, nil)
      |> assign(:reinspect_library_id, nil)
      |> subscribe_status_updates()

    case Libraries.list_libraries(socket.assigns.current_scope.actor) do
      {:ok, libraries} ->
        rows = Enum.map(libraries, &LibraryState.from_domain(&1, %ScanStatus{library_id: &1.id}))
        socket |> stream(:libraries, rows, reset: true) |> FetchScanStatuses.call()

      {:error, _} ->
        socket
        |> assign(
          :error,
          gettext("No se pudieron cargar las bibliotecas. Recarga para reintentar.")
        )
        |> stream(:libraries, [], reset: true)
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
