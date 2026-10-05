defmodule BolognesaWeb.Library.Index.Reducers.StartScan do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [stream_insert: 3]
  alias Bolognesa.Libraries
  alias BolognesaWeb.Library.Index.State.Library
  alias BolognesaWeb.Library.Index.Reducers.{FetchScanStatuses, CancelScanStatuses}

  @spec call(Phoenix.LiveView.Socket.t(), String.t(), keyword()) :: Phoenix.LiveView.Socket.t()
  def call(socket, web_id, opts \\ []) do
    socket = CancelScanStatuses.call(socket)

    with {:ok, id} <- parse_id(web_id),
         {:ok, _scan} <- Libraries.start_scan(socket.assigns.current_scope.actor, id, opts) do
      socket |> refresh_row(id) |> FetchScanStatuses.call()
    else
      {:error, reason} ->
        socket |> assign(:scan_feedback, message(reason)) |> FetchScanStatuses.call()
    end
  end

  defp refresh_row(socket, id) do
    actor = socket.assigns.current_scope.actor

    with {:ok, libraries} <- Libraries.list_libraries(actor),
         library when library != nil <- Enum.find(libraries, &(&1.id == id)),
         {:ok, status} <- Libraries.get_scan_status(actor, id),
         {:ok, counts} <- Libraries.get_inspection_counts(actor, id) do
      row = Library.from_domain(library, status, counts)

      socket
      |> assign(:scan_feedback, nil)
      |> assign(:scan_active_ids, MapSet.put(socket.assigns.scan_active_ids, id))
      |> stream_insert(:libraries, row)
    else
      _ -> assign(socket, :scan_feedback, "Escaneo solicitado. No se pudo actualizar su estado.")
    end
  end

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {value, ""} when value > 0 -> {:ok, value}
      _ -> {:error, :not_found}
    end
  end

  defp parse_id(_), do: {:error, :not_found}
  defp message(:not_found), do: "No se encontró la biblioteca."
  defp message(:forbidden), do: "No tienes permiso para escanear esta biblioteca."
  defp message(:scan_in_progress), do: "Esta biblioteca ya tiene un escaneo activo."
  defp message(_), do: "No se pudo solicitar el escaneo. Vuelve a intentarlo."
end
