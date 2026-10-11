defmodule BolognesaWeb.Series.Index.LiveTest do
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias BolognesaWeb.SeriesFixtures

  setup %{conn: conn} do
    ctx = SeriesFixtures.setup(conn)
    on_exit(fn -> File.rm_rf!(ctx.directory) end)
    ctx
  end

  test "renders the protected series index view", ctx do
    assert {:ok, view, _} = live(ctx.conn, "/series")
    render_async(view)
    assert has_element?(view, "#series-list a[href='/series/#{ctx.series_id}']", "Serie")
    view |> form("#series-search", search: %{query: "Unknown"}) |> render_submit()
    render_async(view)
    assert has_element?(view, "#series-empty")
  end

  test "rejects anonymous visitors", %{conn: _conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(Phoenix.ConnTest.build_conn(), "/series")
  end
end
