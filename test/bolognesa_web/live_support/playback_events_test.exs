defmodule BolognesaWeb.LiveSupport.PlaybackEventsTest do
  use ExUnit.Case, async: true
  alias BolognesaWeb.LiveSupport.PlaybackEvents

  test "a queued preparation poll cannot replace a terminal failure" do
    id = Ecto.UUID.generate()

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        transcode_session: %{id: id},
        transcode_ready?: false,
        playback_phase: :error,
        playback_error: "Terminal failure"
      }
    }

    assert {:noreply, ^socket} = PlaybackEvents.handle_info({:transcode_poll, id}, socket)
  end
end
