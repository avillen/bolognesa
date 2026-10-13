defmodule BolognesaWeb.Music.Index.Reducer.ApplyPage do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [stream: 4]
  alias Bolognesa.Music.Application.UseCases.ListTracks
  alias BolognesaWeb.Music.Index.State.Track
  @type async_result :: {:ok, ListTracks.result()} | {:exit, term()}
  @spec call(Phoenix.LiveView.Socket.t(), reference(), async_result()) ::
          Phoenix.LiveView.Socket.t()
  def call(socket, request_id, result) do
    if socket.assigns.request_id == request_id, do: apply_result(socket, result), else: socket
  end

  defp apply_result(socket, {:ok, {:ok, page}}) do
    socket
    |> assign(:loading?, false)
    |> assign(:error, nil)
    |> assign(:total, page.total)
    |> assign(:page_size, page.page_size)
    |> stream(:tracks, Enum.map(page.items, &Track.from_dto/1), reset: true)
  end

  defp apply_result(socket, _result),
    do:
      socket
      |> assign(:loading?, false)
      |> assign(:error, gettext("No se pudo cargar la música. Puedes reintentar."))
end
