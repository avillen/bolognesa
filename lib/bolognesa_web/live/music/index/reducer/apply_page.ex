defmodule BolognesaWeb.Music.Index.Reducer.ApplyPage do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [stream: 4]
  alias Bolognesa.Music.Application.UseCases.Browse
  alias Bolognesa.Music.Application.UseCases.ListTracks
  alias Bolognesa.Music.Domain.ReadModels.BrowsePage
  alias BolognesaWeb.Music.Index.State.Track
  @type async_result :: {:ok, ListTracks.result() | Browse.result()} | {:exit, term()}
  @spec call(Phoenix.LiveView.Socket.t(), reference(), async_result()) ::
          Phoenix.LiveView.Socket.t()
  def call(socket, request_id, result) do
    if socket.assigns.request_id == request_id, do: apply_result(socket, result), else: socket
  end

  defp apply_result(socket, {:ok, {:ok, %BrowsePage{} = page}}) do
    socket
    |> assign(:loading?, false)
    |> assign(:error, nil)
    |> assign(:has_next?, page.has_next?)
    |> assign(:empty?, empty?(page))
    |> assign(:heading, page.heading)
    |> assign(:visible_track_ids, MapSet.new())
    |> stream(:groups, page.items, reset: true)
    |> stream(:tracks, [], reset: true)
  end

  defp apply_result(socket, {:ok, {:ok, page}}) do
    socket
    |> assign(:loading?, false)
    |> assign(:error, nil)
    # Only album pages are counted; their total feeds the detail heading.
    |> assign(:total, page.total || 0)
    |> assign(:has_next?, page.has_next?)
    |> assign(:empty?, empty?(page))
    |> assign(:page_size, page.page_size)
    |> assign(:album_artist, page.album_artist)
    |> assign(:album_year, page.album_year)
    |> assign(:heading, page.heading)
    |> assign(:visible_track_ids, page.items |> Enum.map(& &1.id) |> MapSet.new())
    |> stream(:groups, [], reset: true)
    |> stream(:tracks, Enum.map(page.items, &Track.from_row/1), reset: true)
  end

  defp apply_result(socket, _result),
    do:
      socket
      |> assign(:loading?, false)
      |> assign(:error, gettext("No se pudo cargar la música. Puedes reintentar."))

  # A page past the end is not an empty library; pagination still offers Previous.
  defp empty?(page), do: page.items == [] and page.page == 1
end
