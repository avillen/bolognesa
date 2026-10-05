defmodule BolognesaWeb.Library.Index.Reducers.Reinspect do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  alias BolognesaWeb.Library.Index.Reducers.StartScan

  @spec prepare(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def prepare(socket, id) when is_binary(id) do
    case Integer.parse(id) do
      {value, ""} when value > 0 -> assign(socket, :reinspect_library_id, value)
      _ -> socket
    end
  end

  @spec cancel(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def cancel(socket), do: assign(socket, :reinspect_library_id, nil)

  @spec confirm(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def confirm(%{assigns: %{reinspect_library_id: id}} = socket, web_id)
      when is_integer(id) do
    if Integer.to_string(id) == web_id,
      do: socket |> cancel() |> StartScan.call(web_id, force_inspection?: true),
      else: cancel(socket)
  end

  def confirm(socket, _web_id), do: cancel(socket)
end
