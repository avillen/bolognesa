defmodule BolognesaWeb.Library.Index.Reducer.PrepareReinspect do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]

  alias BolognesaWeb.Params

  @spec call(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def call(socket, web_id) when is_binary(web_id) do
    with id when is_integer(id) <- Params.positive_integer(web_id),
         %{name: name} <- Enum.find(socket.assigns.navigation_libraries, &(&1.id == id)) do
      assign(socket, :reinspect_target, %{id: id, name: name})
    else
      _ -> socket
    end
  end
end
