defmodule BolognesaWeb.Music.Index.Reducer.ApplyLastListened do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  alias Bolognesa.Music.Application.UseCases.ListRecentAlbums

  @spec call(
          Phoenix.LiveView.Socket.t(),
          reference(),
          {:ok, ListRecentAlbums.result()} | {:exit, term()}
        ) :: Phoenix.LiveView.Socket.t()
  def call(socket, request, result) do
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
