defmodule BolognesaWeb.Series.Season.LiveTest do
  alias Bolognesa.Repo
  alias Bolognesa.Series
  alias Ecto.Changeset
  alias Phoenix.ConnTest
  alias Phoenix.LiveViewTest
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Bolognesa.Series.Domain.ValueObjects.SeasonEntry
  alias Bolognesa.Series.Infrastructure.Repositories.EctoWatchedEntriesRepository
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

  test "each part has its own card with the same episode number", ctx do
    for part <- [1, 2] do
      file = Bolognesa.SeriesFixtures.file(ctx.library.id, "Example S00E01-part#{part}.mp4")
      Bolognesa.SeriesFixtures.identify(file, 0, [1])
    end

    {:ok, view, _} = live(ctx.conn, "/series/seasons/#{ctx.season_id}")
    render_async(view)

    for part <- [1, 2] do
      assert has_element?(
               view,
               "#episode-label-#{ctx.episode_id}-part-#{part}",
               "1. Uno (Parte #{part})"
             )

      assert has_element?(
               view,
               "#episode-play-#{ctx.episode_id}-part-#{part}[href='/episodes/#{ctx.episode_id}?part=#{part}']"
             )
    end

    refute has_element?(view, "#episode-label-#{ctx.episode_id}")
  end

  test "watched entries show their date while unwatched entries stay neutral", ctx do
    [first, second] = ctx.episode_ids
    watched_at = ~U[2026-11-19 10:00:00.000000Z]
    entry = %SeasonEntry{episode_id: first, part_number: nil}
    :ok = EctoWatchedEntriesRepository.upsert(ctx.actor.id, [entry], watched_at)

    {:ok, view, _} = live(ctx.conn, "/series/seasons/#{ctx.season_id}")
    render_async(view)

    assert has_element?(view, "#episode-watched-#{first}", "Visto")

    assert has_element?(
             view,
             "#episode-watched-#{first} time[datetime='2026-11-19']",
             "19/11/2026"
           )

    refute has_element?(view, "#episode-watched-#{second}")
  end

  test "only the watched part shows the watched state", ctx do
    for part <- [1, 2] do
      file = Bolognesa.SeriesFixtures.file(ctx.library.id, "Example S00E01-part#{part}.mp4")
      Bolognesa.SeriesFixtures.identify(file, 0, [1])
    end

    entry = %SeasonEntry{episode_id: ctx.episode_id, part_number: 2}

    :ok =
      EctoWatchedEntriesRepository.upsert(ctx.actor.id, [entry], ~U[2026-11-19 10:00:00.000000Z])

    {:ok, view, _} = live(ctx.conn, "/series/seasons/#{ctx.season_id}")
    render_async(view)

    assert has_element?(view, "#episode-watched-#{ctx.episode_id}-part-2", "Visto")
    refute has_element?(view, "#episode-watched-#{ctx.episode_id}-part-1")
  end

  test "rejects anonymous visitors", %{conn: _conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(ConnTest.build_conn(), "/series")
  end

  test "malformed page input does not crash the view", ctx do
    assert {:ok, view, _} = live(ctx.conn, "/series/seasons/#{ctx.season_id}?page[]=1")
    render_async(view)
  end

  test "episode play and detail links are separate and return to the series", ctx do
    {:ok, view, _} = live(ctx.conn, "/series/seasons/#{ctx.season_id}")
    render_async(view)
    assert has_element?(view, "#season-back[href='/series/#{ctx.series_id}']")

    assert has_element?(
             view,
             "#episode-play-#{ctx.episode_id}[href='/episodes/#{ctx.episode_id}']"
           )

    refute has_element?(view, "#episode-list a a")
    refute has_element?(view, "#episode-list", "1 de 1")
  end

  test "unavailable episodes keep their detail link without a play action", ctx do
    ctx.media_file
    |> Changeset.change(availability: :missing)
    |> Repo.update!()

    {:ok, view, _} = live(ctx.conn, "/series/seasons/#{ctx.season_id}")
    render_async(view)
    assert has_element?(view, "#episode-list a[href='/episodes/#{ctx.episode_id}']")
    refute has_element?(view, "#episode-play-#{ctx.episode_id}")
    assert has_element?(view, "#episode-availability-#{ctx.episode_id}", "No disponible")
  end

  test "marking the season watched covers unavailable entries and leaves cards without actions",
       ctx do
    ctx.media_file |> Changeset.change(availability: :missing) |> Repo.update!()
    {:ok, view, _} = live(ctx.conn, "/series/seasons/#{ctx.season_id}")
    render_async(view)
    refute has_element?(view, "#episode-list button")
    refute has_element?(view, "#episode-watched-#{ctx.episode_id}")

    assert view
           |> element("#season-watched-action", "Marcar temporada como vista")
           |> render_click() =~
             "Temporada marcada como vista."

    render_async(view)
    assert has_element?(view, "#episode-watched-#{ctx.episode_id}", "Visto")

    assert {:ok, entries} =
             Series.list_watched_entries(ctx.actor, {:season, ctx.season_id})

    assert Enum.map(entries, & &1.episode_id) == Enum.sort(ctx.episode_ids)
  end
end
