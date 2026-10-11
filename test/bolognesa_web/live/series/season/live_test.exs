defmodule BolognesaWeb.Series.Season.LiveTest do
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias BolognesaWeb.SeriesFixtures

  setup %{conn: conn} do
    ctx = SeriesFixtures.setup(conn)
    on_exit(fn -> File.rm_rf!(ctx.directory) end)
    ctx
  end

  test "renders the protected series season view", ctx do
    assert {:ok, view, _} = live(ctx.conn, "/series/seasons/#{ctx.season_id}")
    render_async(view)
    assert has_element?(view, "#season-title", "Especiales")
    assert has_element?(view, "#episode-list a[href='/episodes/#{ctx.episode_id}']")
  end

  test "rejects anonymous visitors", %{conn: _conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(Phoenix.ConnTest.build_conn(), "/series")
  end

  test "malformed page input does not crash the view", ctx do
    assert {:ok, view, _} = live(ctx.conn, "/series/seasons/#{ctx.season_id}?page[]=1")
    render_async(view)
  end
end
