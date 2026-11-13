defmodule BolognesaWeb.Library.Index.Reducer.Reinspect do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]

  alias BolognesaWeb.Library.Index.Reducer.StartScan

  @spec call(Phoenix.LiveView.Socket.t(), :prepare | :confirm, String.t()) ::
          Phoenix.LiveView.Socket.t()
  def call(socket, :prepare, web_id) when is_binary(web_id) do
    with {id, ""} when id > 0 <- Integer.parse(web_id),
         %{name: name} <- Enum.find(socket.assigns.navigation_libraries, &(&1.id == id)) do
      assign(socket, :reinspect_target, %{id: id, name: name})
    else
      _ -> socket
    end
  end

  def call(%{assigns: %{reinspect_target: %{id: id}}} = socket, :confirm, web_id)
      when is_integer(id) do
    if Integer.to_string(id) == web_id,
      do: socket |> cancel() |> StartScan.call(web_id, force_inspection?: true),
      else: cancel(socket)
  end

  def call(socket, :confirm, _web_id), do: cancel(socket)

  @spec call(Phoenix.LiveView.Socket.t(), :cancel) :: Phoenix.LiveView.Socket.t()
  def call(socket, :cancel), do: cancel(socket)

  defp cancel(socket), do: assign(socket, :reinspect_target, nil)
end
