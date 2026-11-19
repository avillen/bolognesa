defmodule BolognesaWeb.Series.Show.Reducer.LoadContinueTarget do
  @moduledoc false
  import Phoenix.LiveView, only: [start_async: 3]
  alias Bolognesa.Series
  @spec call(Phoenix.LiveView.Socket.t(), integer()) :: Phoenix.LiveView.Socket.t()
  def call(socket, id) do
    actor = socket.assigns.current_scope.actor
    start_async(socket, {:continue_target, id}, fn -> Series.fetch_continue_target(actor, id) end)
  end
end
