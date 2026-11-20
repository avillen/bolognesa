defmodule BolognesaWeb.Series.Index.Reducer.LoadRecentSeries do
  @moduledoc "Loads the account's recently watched series independently of the catalog."
  import Phoenix.LiveView, only: [start_async: 3]
  alias Bolognesa.Series

  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(socket) do
    actor = socket.assigns.current_scope.actor
    library_id = socket.assigns.active_library_id

    start_async(socket, :recent_series, fn -> Series.list_recent_series(actor, library_id) end)
  end
end
