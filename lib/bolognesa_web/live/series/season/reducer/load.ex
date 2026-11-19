defmodule BolognesaWeb.Series.Season.Reducer.Load do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [start_async: 3]
  alias Bolognesa.Series
  @spec call(Phoenix.LiveView.Socket.t(), integer(), pos_integer()) :: Phoenix.LiveView.Socket.t()
  def call(socket, id, page) do
    actor = socket.assigns.current_scope.actor
    request = make_ref()

    socket
    |> assign(content_id: id, page: page, request_id: request, loading?: true, error: nil)
    |> start_async({:season_episodes, request}, fn -> Series.list_episodes(actor, id, page) end)
  end
end
