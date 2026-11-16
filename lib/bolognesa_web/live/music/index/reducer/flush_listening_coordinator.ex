defmodule BolognesaWeb.Music.Index.Reducer.FlushListeningCoordinator do
  @moduledoc "Refreshes the listening activity deferred while a page loaded, once it loads."
  import Phoenix.Component, only: [assign: 3]
  alias BolognesaWeb.Music.Index.Reducer.RefreshListening

  @spec call(Phoenix.LiveView.Socket.t(), term()) :: Phoenix.LiveView.Socket.t()
  def call(socket, result) do
    pending = socket.assigns.pending_listening
    socket = assign(socket, :pending_listening, MapSet.new())

    case result do
      {:ok, {:ok, _page}} -> Enum.reduce(pending, socket, &RefreshListening.call(&2, &1))
      _ -> socket
    end
  end
end
