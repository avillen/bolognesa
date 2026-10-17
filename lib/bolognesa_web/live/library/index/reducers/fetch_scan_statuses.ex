defmodule BolognesaWeb.Library.Index.Reducers.FetchScanStatuses do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 3, connected?: 1]

  alias Bolognesa.Libraries

  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(%{assigns: %{scan_loading?: true}} = socket),
    do: assign(socket, :scan_refresh_pending?, true)

  def call(socket) do
    if connected?(socket), do: fetch(socket), else: socket
  end

  defp fetch(socket) do
    actor = socket.assigns.current_scope.actor
    request_id = make_ref()

    socket
    |> assign(:scan_refresh_pending?, false)
    |> assign(:scan_request_id, request_id)
    |> assign(:scan_loading?, true)
    |> start_async({:scan_statuses, request_id}, fn -> load(actor) end)
  end

  defp load(actor) do
    with {:ok, libraries} <- Libraries.list_libraries(actor) do
      Enum.reduce_while(libraries, {:ok, []}, fn library, {:ok, rows} ->
        load_library(actor, library, rows)
      end)
      |> ordered()
    end
  end

  defp load_library(actor, library, rows) do
    with {:ok, status} <- Libraries.fetch_scan_status(actor, library.id),
         {:ok, counts} <- Libraries.fetch_inspection_counts(actor, library.id) do
      {:cont, {:ok, [{library, status, counts} | rows]}}
    else
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp ordered({:ok, rows}), do: {:ok, Enum.reverse(rows)}
  defp ordered(error), do: error
end
