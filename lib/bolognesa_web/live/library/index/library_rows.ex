defmodule BolognesaWeb.Library.Index.LibraryRows do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [stream: 3, stream: 4, stream_insert: 4, stream_delete: 3]

  alias BolognesaWeb.Library.Index.State.Library

  @spec initialize(Phoenix.LiveView.Socket.t(), [Library.t()]) :: Phoenix.LiveView.Socket.t()
  def initialize(socket, rows) do
    socket
    |> assign(:rendered_library_ids, MapSet.new(rows, & &1.id))
    |> stream(:libraries, rows, reset: true)
  end

  @spec insert(Phoenix.LiveView.Socket.t(), Library.t(), integer()) :: Phoenix.LiveView.Socket.t()
  def insert(socket, row, at \\ -1) do
    socket
    |> assign(:rendered_library_ids, MapSet.put(socket.assigns.rendered_library_ids, row.id))
    |> stream_insert(:libraries, row, at: at)
  end

  @spec sync(Phoenix.LiveView.Socket.t(), [Library.t()]) :: Phoenix.LiveView.Socket.t()
  def sync(socket, rows) do
    current_ids = MapSet.new(rows, & &1.id)
    removed_ids = MapSet.difference(socket.assigns.rendered_library_ids, current_ids)

    # A stream reset detaches even retained rows and loses keyboard focus.
    # Update them in place and remove only libraries absent from the new result.
    socket = Enum.reduce(removed_ids, socket, &stream_delete(&2, :libraries, %{id: &1}))

    socket
    |> assign(:rendered_library_ids, current_ids)
    |> stream(:libraries, rows)
  end
end
