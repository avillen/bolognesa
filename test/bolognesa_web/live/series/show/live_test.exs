defmodule BolognesaWeb.Series.Show.LiveTest do
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias BolognesaWeb.SeriesFixtures

  setup %{conn: conn} do
    ctx = SeriesFixtures.setup(conn)
    on_exit(fn -> File.rm_rf!(ctx.directory) end)
    ctx
  end

  test "renders the protected series show view", ctx do
    assert {:ok, view, _} = live(ctx.conn, "/series/#{ctx.series_id}")
    render_async(view)
    assert has_element?(view, "#series-title", "Serie")

    assert has_element?(
             view,
             "#season-list a[href='/series/seasons/#{ctx.season_id}']",
             "Especiales"
           )
  end

  test "rejects anonymous visitors", %{conn: _conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(Phoenix.ConnTest.build_conn(), "/series")
  end

  test "malformed page input does not crash the view", ctx do
    assert {:ok, view, _} = live(ctx.conn, "/series/#{ctx.series_id}?page[]=1")
    render_async(view)
  end

  test "a long synopsis starts collapsed below the hero", ctx do
    Bolognesa.Repo.get!(Bolognesa.Infrastructure.Persistence.SeriesSchema, ctx.series_id)
    |> Ecto.Changeset.change(overview: String.duplicate("Series overview. ", 30))
    |> Bolognesa.Repo.update!()

    {:ok, view, _} = live(ctx.conn, "/series/#{ctx.series_id}")
    render_async(view)

    assert has_element?(
             view,
             ".series-seasons-body details#series-synopsis:not([open])",
             "Series overview."
           )

    assert has_element?(view, ".media-hero-copy", "1 temporada en tu biblioteca")
  end
end
