defmodule BolognesaWeb.Library.Index.Reducers.Reinspect do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]

  alias BolognesaWeb.Library.Index.Reducers.StartScan

  @spec prepare(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def prepare(socket, web_id) when is_binary(web_id) do
    with {id, ""} when id > 0 <- Integer.parse(web_id),
         %{name: name} <- Enum.find(socket.assigns.navigation_libraries, &(&1.id == id)) do
      assign(socket, :reinspect_target, %{id: id, name: name})
    else
      _ -> socket
    end
  end

  @spec cancel(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def cancel(socket), do: assign(socket, :reinspect_target, nil)

  @spec confirm(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def confirm(%{assigns: %{reinspect_target: %{id: id}}} = socket, web_id)
      when is_integer(id) do
    if Integer.to_string(id) == web_id,
      do: socket |> cancel() |> StartScan.call(web_id, force_inspection?: true),
      else: cancel(socket)
  end

  def confirm(socket, _web_id), do: cancel(socket)
end
