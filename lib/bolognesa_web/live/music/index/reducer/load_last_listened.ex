defmodule BolognesaWeb.Music.Index.Reducer.LoadLastListened do
  @moduledoc "Loads the account-scoped recent albums independently of the music list."
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 3]
  alias Bolognesa.Music

  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(%{assigns: %{last_listened_visible?: false}} = socket), do: socket

  def call(socket) do
    actor = socket.assigns.current_scope.actor
    library = socket.assigns.active_library_id
    request = make_ref()

    socket
    |> assign(:last_listened_request, request)
    |> start_async({:last_listened, request}, fn ->
      Music.list_recent_albums(actor, library)
    end)
  end
end
