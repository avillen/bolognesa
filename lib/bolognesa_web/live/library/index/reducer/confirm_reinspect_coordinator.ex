defmodule BolognesaWeb.Library.Index.Reducer.ConfirmReinspectCoordinator do
  @moduledoc "Starts the prepared forced scan only when the confirmed library matches it."
  import Phoenix.Component, only: [assign: 3]

  alias BolognesaWeb.Library.Index.Reducer.FetchScanStatuses
  alias BolognesaWeb.Library.Index.Reducer.StartScan

  @spec call(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def call(%{assigns: %{reinspect_target: %{id: id}}} = socket, web_id) when is_integer(id) do
    socket = assign(socket, :reinspect_target, nil)

    if Integer.to_string(id) == web_id,
      do: socket |> StartScan.call(web_id, force_inspection?: true) |> FetchScanStatuses.call(),
      else: socket
  end

  def call(socket, _web_id), do: assign(socket, :reinspect_target, nil)
end
