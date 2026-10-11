defmodule BolognesaWeb.Episode.Show.LiveTest do
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
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

    render_hook(view, "playback_error", %{file_id: Integer.to_string(ctx.media_file.id)})
    assert has_element?(view, "#episode-compatible-#{ctx.media_file.id}")
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
