defmodule BolognesaWeb.Music.Index.Reducer.ResetLastListened do
  @moduledoc "Clears the recent albums and shows them only on the music home view."
  import Phoenix.Component, only: [assign: 3]

  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(socket) do
    socket
    |> assign(:last_listened_visible?, socket.assigns.browse_kind == :home)
    |> assign(:recent_albums, [])
    |> assign(:last_listened_request, nil)
    |> assign(:last_listened_status, :loading)
  end
end
