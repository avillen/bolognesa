defmodule BolognesaWeb.PlayerTest do
  alias BolognesaWeb.Player, as: BolognesaWebPlayer
  alias Phoenix.LiveViewTest
  use BolognesaWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "checking mounts the stable frame without any delivery URL or autoplay" do
    html =
      render_component(&BolognesaWebPlayer.player/1,
        prefix: "movie",
        kind: :movie,
        entry_id: 1,
        viewer_id: 1,
        selected_file_id: 2,
        playback_phase: :checking,
        playback_probe: %{generation: "g1", candidates: []},
        delivery_plan: nil,
        transcode_ready?: false,
        transcode_paused?: false,
        transcode_autoplay?: false
      )

    assert html =~ ~s(phx-hook="VideoPlayer")
    assert html =~ ~s(id="movie-video-ui" phx-update="ignore")
    refute html =~ "data-src="
    refute html =~ " src="
    refute html =~ " autoplay"
    assert html =~ ~s(data-playback-phase="checking")
  end
end
