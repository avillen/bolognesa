defmodule BolognesaWeb.PlayerTest do
  alias BolognesaWeb.LiveSupport.PlaybackAttempt
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
        attempt: %PlaybackAttempt{
          file_id: 2,
          phase: :checking,
          probe: %{generation: "g1", candidates: []}
        }
      )

    assert html =~ ~s(phx-hook="VideoPlayer")
    assert html =~ ~s(id="movie-video-ui" phx-update="ignore")
    refute html =~ "data-src="
    refute html =~ " src="
    refute html =~ " autoplay"
    assert html =~ ~s(data-playback-phase="checking")
  end
end
