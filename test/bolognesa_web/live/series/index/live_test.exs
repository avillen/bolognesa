defmodule BolognesaWeb.Series.Index.LiveTest do
  alias Phoenix.ConnTest
  alias Phoenix.LiveViewTest
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Bolognesa.Series.Domain.ValueObjects.Entry
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
        [%Entry{episode_id: first, part_number: nil}],
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

    {:ok, view, _} = live(ctx.conn, "/series?query=Serie")
    render_async(view)
    refute has_element?(view, "#series-continue-shelf")
  end

  test "a new search cancels the superseded catalog read", ctx do
    watch_reads(fn _query, params -> "Seri" in params end, fn _params -> true end)
    {:ok, view, _} = live(ctx.conn, "/series?query=Seri")
    assert_receive {:read, reader, _params}
    monitor = Process.monitor(reader)
    render_patch(view, "/series?query=Serie")
    assert_receive {:DOWN, ^monitor, :process, ^reader, {:shutdown, :cancel}}
    render_async(view)
    assert has_element?(view, "#series-list #series-#{ctx.series_id}")
  end

  test "the Continue shelf survives search and paging and clears on a library switch", ctx do
    continue = watch_next_episode(ctx)
    other = Bolognesa.SeriesFixtures.library()
    watch_reads(&recent_read?/2, &(other.id in &1))
    {:ok, view, _} = live(ctx.conn, "/series?library_id=#{ctx.library.id}")
    render_async(view)
    assert_received {:read, _reader, params}
    assert ctx.library.id in params
    assert has_element?(view, continue)

    render_patch(view, "/series?library_id=#{ctx.library.id}&query=Serie")
    render_patch(view, "/series?library_id=#{ctx.library.id}&page=2")
    render_patch(view, "/series?library_id=#{ctx.library.id}")
    assert has_element?(view, continue)
    render_async(view)
    refute_received {:read, _reader, _params}

    render_patch(view, "/series?library_id=#{other.id}")
    assert_receive {:read, reader, params}
    assert other.id in params
    refute has_element?(view, continue)
    send(reader, :continue)
    render_async(view)
    refute has_element?(view, "#series-continue-shelf")
  end

  test "a failed Continue shelf read is retried by the next navigation", ctx do
    continue = watch_next_episode(ctx)
    watch_reads(&recent_read?/2, fn _params -> true end)
    {:ok, view, _} = live(ctx.conn, "/series?library_id=#{ctx.library.id}")
    assert_receive {:read, reader, _params}
    Process.exit(reader, :kill)
    render_async(view)
    refute has_element?(view, "#series-continue-shelf")

    render_patch(view, "/series?library_id=#{ctx.library.id}&query=Serie")
    assert_receive {:read, reader, _params}
    send(reader, :continue)
    render_patch(view, "/series?library_id=#{ctx.library.id}")
    render_async(view)
    assert has_element?(view, continue)
  end

  # Marks the first episode of a new season watched and returns the selector of its Continue link.
  defp watch_next_episode(ctx) do
    file = Bolognesa.SeriesFixtures.file(ctx.library.id, "Serie S01E01E02.mp4")
    [first, second] = Bolognesa.SeriesFixtures.identify(file, 1, [1, 2]).episode_ids

    :ok =
      Repository.upsert(
        ctx.actor.id,
        [%Entry{episode_id: first, part_number: nil}],
        DateTime.utc_now()
      )

    "#recent-series-continue-#{ctx.series_id}[href='/episodes/#{second}']"
  end

  defp recent_read?(query, _params),
    do: query =~ ~r/FROM "series_watched_entries" AS \w+ INNER JOIN "episodes"/

  # Reports each matching repo read to the test; reads accepted by `park?` wait for :continue.
  defp watch_reads(match?, park?) do
    handler = {__MODULE__, make_ref()}
    parent = self()

    :ok =
      :telemetry.attach(
        handler,
        [:bolognesa, :repo, :query],
        fn _, _, %{query: query, params: params}, _ ->
          if match?.(query, params) do
            send(parent, {:read, self(), params})

            if park?.(params) do
              receive do
                :continue -> :ok
              after
                10_000 -> :ok
              end
            end
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
  end
end
