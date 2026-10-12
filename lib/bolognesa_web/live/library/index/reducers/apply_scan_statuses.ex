defmodule BolognesaWeb.Library.Index.Reducers.ApplyScanStatuses do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [stream: 4]

  alias Bolognesa.Libraries.Domain.Entities.Library
  alias Bolognesa.Libraries.Domain.ReadModels.Scans.InspectionCounts
  alias Bolognesa.Libraries.Domain.ReadModels.Scans.ScanStatus
  alias BolognesaWeb.Library.Index.Reducers.FetchScanStatuses

  @refresh_failure "No se pudo actualizar el escaneo. Vuelve a intentarlo."

  @type result ::
          {:ok, {:ok, [{Library.t(), ScanStatus.t(), InspectionCounts.t()}]} | {:error, atom()}}
          | {:exit, term()}
  @spec call(Phoenix.LiveView.Socket.t(), reference(), result()) :: Phoenix.LiveView.Socket.t()
  def call(%{assigns: %{scan_request_id: current}} = socket, request_id, result)
      when current == request_id do
    socket
    |> assign(:scan_loading?, false)
    |> apply_result(result)
    |> refresh_pending()
  end

  def call(socket, _request_id, _result), do: socket

  defp apply_result(socket, {:ok, {:ok, pairs}}) do
    rows =
      Enum.map(pairs, fn {library, status, counts} ->
        BolognesaWeb.Library.Index.State.Library.from_domain(library, status, counts)
      end)

    socket
    |> clear_refresh_failure()
    |> stream(:libraries, rows, reset: true)
  end

  defp apply_result(socket, _error) do
    assign(socket, :scan_feedback, gettext(@refresh_failure))
  end

  defp clear_refresh_failure(socket) do
    if socket.assigns.scan_feedback == gettext(@refresh_failure),
      do: assign(socket, :scan_feedback, nil),
      else: socket
  end

  defp refresh_pending(%{assigns: %{scan_refresh_pending?: true}} = socket),
    do: FetchScanStatuses.call(socket)

  defp refresh_pending(socket), do: socket
end
