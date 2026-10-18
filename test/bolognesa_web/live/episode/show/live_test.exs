defmodule BolognesaWeb.Episode.Show.LiveTest do
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Bolognesa.Playback.Infrastructure.TranscodeManager
  alias BolognesaWeb.SeriesFixtures

  setup %{conn: conn} do
    ctx = SeriesFixtures.setup(conn)
    on_exit(fn -> File.rm_rf!(ctx.directory) end)
    ctx
  end

  test "shows a multi episode warning and starts the selected complete file", ctx do
    {:ok, view, _} = live(ctx.conn, "/episodes/#{ctx.episode_id}")
    render_async(view)
    assert has_element?(view, "#multi-episode-notice", "principio del archivo")
    view |> element("#episode-play-#{ctx.media_file.id}") |> render_click()

    assert has_element?(
             view,
             "#episode-video-#{ctx.media_file.id}[src='/episodes/#{ctx.episode_id}/media/#{ctx.media_file.id}']"
           )

    executable = Path.join(ctx.directory, "fake-ffmpeg")
    File.write!(executable, "#!/bin/sh\nwhile :; do sleep 1; done\n")
    File.chmod!(executable, 0o700)
    old_executable = Application.get_env(:bolognesa, :ffmpeg_executable)
    Application.put_env(:bolognesa, :ffmpeg_executable, executable)

    on_exit(fn ->
      TranscodeManager.stop_all()

      if old_executable,
        do: Application.put_env(:bolognesa, :ffmpeg_executable, old_executable),
        else: Application.delete_env(:bolognesa, :ffmpeg_executable)
    end)

    render_hook(view, "playback_error", %{
      file_id: Integer.to_string(ctx.media_file.id),
      position_ms: "invalid"
    })

    assert has_element?(view, "#episode-playback-preparing[role='status']")
    refute has_element?(view, "#episode-player video")
    refute has_element?(view, "#episode-playback-error")
  end

  test "direct delivery checks each episode association and supports ranges", ctx do
    for id <- ctx.episode_ids do
      conn =
        ctx.conn
        |> put_req_header("range", "bytes=2-4")
        |> get("/episodes/#{id}/media/#{ctx.media_file.id}")

      assert response(conn, 206) == "cde"
    end

    conn = get(ctx.conn, "/episodes/#{ctx.series_id}/media/#{ctx.media_file.id}")
    assert response(conn, 404) == ""

    conn =
      get(Phoenix.ConnTest.build_conn(), "/episodes/#{ctx.episode_id}/media/#{ctx.media_file.id}")

    assert response(conn, 401) == ""
  end
end
