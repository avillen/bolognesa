defmodule BolognesaWeb.Music.Index.Reducer.LastListened do
  @moduledoc "Loads the account-scoped recent albums independently of the music list."
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 3]
  alias Bolognesa.Music
  alias Bolognesa.Music.Application.UseCases.ListRecentAlbums

  @type operation ::
          :reset | :load | {:result, reference(), {:ok, ListRecentAlbums.result()} | {:exit, term()}}

  @spec call(Phoenix.LiveView.Socket.t(), operation()) :: Phoenix.LiveView.Socket.t()
  def call(socket, :reset) do
    visible? = socket.assigns.browse_kind == :home

    socket
    |> assign(:last_listened_visible?, visible?)
    |> assign(:recent_albums, [])
    |> assign(:last_listened_request, nil)
    |> assign(:last_listened_status, :loading)
    |> call(:load)
  end

  def call(%{assigns: %{last_listened_visible?: false}} = socket, :load), do: socket

  def call(socket, :load) do
    actor = socket.assigns.current_scope.actor
    library = socket.assigns.active_library_id
    request = make_ref()

    socket
    |> assign(:last_listened_request, request)
    |> start_async({:last_listened, request}, fn ->
      Music.list_recent_albums(actor, library)
    end)
  end

  def call(socket, {:result, request, result}) do
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
