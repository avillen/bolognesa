defmodule BolognesaWeb.Music.Index.Reducer.LastListened do
  @moduledoc "Loads the account-scoped recent albums independently of the music list."
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 3]
  alias Bolognesa.Music
  alias Bolognesa.Music.Application.UseCases.ListRecentAlbums

  @spec reset(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def reset(socket) do
    visible? = socket.assigns.browse_kind == :home

    socket
    |> assign(:last_listened_visible?, visible?)
    |> assign(:recent_albums, [])
    |> assign(:last_listened_request, nil)
    |> assign(:last_listened_status, :loading)
    |> load()
  end

  @spec load(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def load(%{assigns: %{last_listened_visible?: false}} = socket), do: socket

  def load(socket) do
    actor = socket.assigns.current_scope.actor
    library = socket.assigns.active_library_id
    request = make_ref()

    socket
    |> assign(:last_listened_request, request)
    |> start_async({:last_listened, request}, fn ->
      Music.list_recent_albums(actor, library)
    end)
  end

  @spec apply_result(
          Phoenix.LiveView.Socket.t(),
          reference(),
          {:ok, ListRecentAlbums.result()} | {:exit, term()}
        ) :: Phoenix.LiveView.Socket.t()
  def apply_result(socket, request, result) do
    if socket.assigns.last_listened_request == request,
      do: apply_current(socket, result),
      else: socket
  end

  defp apply_current(socket, {:ok, {:ok, albums}}) do
    socket
    |> assign(:recent_albums, albums)
    |> assign(:last_listened_status, if(albums == [], do: :empty, else: :ready))
  end

  defp apply_current(socket, _result), do: assign(socket, :last_listened_status, :error)
end
