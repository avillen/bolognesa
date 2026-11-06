defmodule BolognesaWeb.Music.Index.Reducer.LastListenedTest do
  use ExUnit.Case, async: true
  alias Bolognesa.Music.Application.Dto.RecentAlbum
  alias BolognesaWeb.Music.Index.Reducer.LastListened

  test "obsolete results cannot restore an album after navigation or a newer activity read" do
    current = make_ref()

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        last_listened_request: current,
        recent_albums: [],
        last_listened_status: :loading
      }
    }

    album = %RecentAlbum{id: 1, title: "Record"}
    assert socket == LastListened.apply_result(socket, make_ref(), {:ok, {:ok, [album]}})
    assert socket == LastListened.apply_result(socket, make_ref(), {:ok, {:ok, []}})
    assert socket == LastListened.apply_result(socket, make_ref(), {:exit, :shutdown})

    failed = LastListened.apply_result(socket, current, {:ok, {:error, :unavailable}})
    assert failed.assigns.last_listened_status == :error
    empty = LastListened.apply_result(failed, current, {:ok, {:ok, []}})
    assert empty.assigns.last_listened_status == :empty
    assert empty.assigns.recent_albums == []
  end
end
