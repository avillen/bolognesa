defmodule BolognesaWeb.Series.Index.LiveTest do
  alias Phoenix.ConnTest
  alias Phoenix.LiveViewTest
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Bolognesa.Series.Domain.ValueObjects.SeasonEntry
  alias Bolognesa.Series.Infrastructure.Repositories.EctoWatchedEntriesRepository, as: Repository
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
    view |> form("#series-search", search: %{query: "Unknown"}) |> render_change()
    render_async(view)
    assert has_element?(view, "#series-empty")
  end

  test "rejects anonymous visitors", %{conn: _conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(ConnTest.build_conn(), "/series")
  end

  test "library search and detail navigation retain the selected library", ctx do
    route = "/series?library_id=#{ctx.library.id}"
    {:ok, view, _} = live(ctx.conn, route)
    render_async(view)
    assert has_element?(view, "#nav-library-#{ctx.library.id}[aria-current=page]")
    view |> form("#series-search", search: %{query: "Serie"}) |> render_submit()
    assert_patch(view, route <> "&query=Serie")
    render_async(view)
    result = view |> element("#series-list a") |> render_click()
    {:ok, detail, _} = follow_redirect(result, ctx.conn)
    render_async(detail)
    assert has_element?(detail, "#nav-library-#{ctx.library.id}[aria-current=page]")
    assert has_element?(detail, "a[href='/series?library_id=#{ctx.library.id}&query=Serie']")

    assert has_element?(
             detail,
             "a[href='/series/seasons/#{ctx.season_id}?catalog_query=Serie&library_id=#{ctx.library.id}']"
           )
  end

  test "search without results offers a reset rather than setup instructions", ctx do
    {:ok, view, _} = live(ctx.conn, "/series?query=Unknown")
    render_async(view)
    assert has_element?(view, "#series-clear-search")
    refute has_element?(view, "#series-empty", "Añade una biblioteca")
    assert has_element?(view, "#series-library-options #series-review-link")
    assert has_element?(view, "#app-menu-toggle[aria-controls=app-navigation]")
  end

  test "an empty series library excludes titles from other sources", ctx do
    library = Bolognesa.SeriesFixtures.library()
    {:ok, view, _} = live(ctx.conn, "/series?library_id=#{library.id}")
    render_async(view)
    assert has_element?(view, "#series-empty")
    refute has_element?(view, "#series-list a")
  end

  test "shows the Continue shelf only for watched series", ctx do
    file = Bolognesa.SeriesFixtures.file(ctx.library.id, "Serie S01E01E02.mp4")
    [first, second] = Bolognesa.SeriesFixtures.identify(file, 1, [1, 2]).episode_ids
    {:ok, view, _} = live(ctx.conn, "/series")
    render_async(view)
    refute has_element?(view, "#series-continue-shelf")

    :ok =
      Repository.upsert(
        ctx.actor.id,
        [%SeasonEntry{episode_id: first, part_number: nil}],
        DateTime.utc_now()
      )

    {:ok, view, _} = live(ctx.conn, "/series")
    render_async(view)

    assert has_element?(
             view,
             "#recent-series-continue-#{ctx.series_id}[href='/episodes/#{second}']",
             "Continuar T1·E2"
           )

    assert has_element?(view, "#series-list #series-#{ctx.series_id}")
  end
end
