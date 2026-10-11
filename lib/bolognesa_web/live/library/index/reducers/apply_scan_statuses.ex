defmodule BolognesaWeb.Library.Index.Reducers.ApplyScanStatuses do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [stream: 4, connected?: 1]

  alias Bolognesa.Libraries.Domain.Library
  alias Bolognesa.Libraries.Domain.ScanStatus

  @refresh_failure "No se pudo actualizar el escaneo. Vuelve a intentarlo."

  @type result ::
          {:ok, {:ok, [{Library.t(), ScanStatus.t()}]} | {:error, atom()}}
          | {:exit, term()}
  @spec call(Phoenix.LiveView.Socket.t(), reference(), result()) :: Phoenix.LiveView.Socket.t()
  def call(%{assigns: %{scan_request_id: current}} = socket, request_id, result)
      when current == request_id do
    socket
    |> assign(:scan_loading?, false)
    |> apply_result(result)
    |> schedule()
  end

  def call(socket, _request_id, _result), do: socket

  defp apply_result(socket, {:ok, {:ok, pairs}}) do
    rows =
      Enum.map(pairs, fn {library, status, counts} ->
        BolognesaWeb.Library.Index.State.Library.from_domain(library, status, counts)
      end)

    active_ids =
      for row <- rows, row.active? or row.inspection_active?, into: MapSet.new(), do: row.id

    socket
    |> assign(:scan_active_ids, active_ids)
    |> clear_refresh_failure()
    |> stream(:libraries, rows, reset: true)
  end

  defp apply_result(socket, _error) do
    assign(socket, :scan_feedback, @refresh_failure)
  end

  defp clear_refresh_failure(%{assigns: %{scan_feedback: @refresh_failure}} = socket),
    do: assign(socket, :scan_feedback, nil)

  defp clear_refresh_failure(socket), do: socket

  defp schedule(socket) do
    if connected?(socket) and MapSet.size(socket.assigns.scan_active_ids) > 0,
      do:
        assign(socket, :scan_timer_ref, Process.send_after(self(), :refresh_scan_statuses, 2_000)),
      else: socket
  end
end
