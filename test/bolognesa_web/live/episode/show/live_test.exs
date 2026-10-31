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

  test "automatically loads the first version and shows the multi episode warning", ctx do
    {:ok, view, _} = live(ctx.conn, "/episodes/#{ctx.episode_id}")
    render_async(view)
    assert has_element?(view, "#multi-episode-notice", "principio del archivo")

    assert has_element?(
             view,
             "#episode-video-frame[data-video-id='episode-video-#{ctx.media_file.id}'][data-autoplay='true'][data-src='/episodes/#{ctx.episode_id}/media/#{ctx.media_file.id}']"
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
    refute has_element?(view, "#episode-video-frame[data-src]")
    refute has_element?(view, "#episode-playback-error")
  end

  test "a part link opens its own file and navigation follows parts", ctx do
    first = add_part(ctx, 1)
    second = add_part(ctx, 2)
    {:ok, view, _} = live(ctx.conn, "/episodes/#{ctx.episode_id}?part=1&season_page=3")
    render_async(view)
    assert has_element?(view, "#episode-title", "Uno (Parte 1)")
    assert has_element?(view, "#episode-video-frame[data-video-id='episode-video-#{first.id}']")

    assert has_element?(
             view,
             "#episode-next[href='/episodes/#{ctx.episode_id}?part=2&season_page=3']"
           )

    refute has_element?(view, "#episode-play-#{second.id}")
    render_hook(view, "playback_ended", %{file_id: to_string(first.id)})
    render_async(view)
    assert_patch(view, "/episodes/#{ctx.episode_id}?part=2&season_page=3")

    second_view = view
    assert has_element?(second_view, "#episode-title", "Uno (Parte 2)")

    assert has_element?(
             second_view,
             "#episode-video-frame[data-video-id='episode-video-#{second.id}']"
           )

    assert has_element?(
             second_view,
             "#episode-previous[href='/episodes/#{ctx.episode_id}?part=1&season_page=3']"
           )
  end

  test "missing and invalid parts do not substitute another file", ctx do
    first = add_part(ctx, 1)
    second = add_part(ctx, 2)
    mark_unavailable(second)
    {:ok, view, _} = live(ctx.conn, "/episodes/#{ctx.episode_id}?part=1")
    render_async(view)
    render_hook(view, "playback_ended", %{file_id: to_string(first.id)})
    render_async(view)
    assert has_element?(view, "[role='alert']", "parte")

    {:ok, missing, _} = live(ctx.conn, "/episodes/#{ctx.episode_id}?part=2")
    render_async(missing)
    refute has_element?(missing, "#episode-video-frame[data-src]")
    assert has_element?(missing, "#episode-unavailable")

    for query <- ["part=99", "part=bad", "part[]=1"] do
      {:ok, invalid, _} = live(ctx.conn, "/episodes/#{ctx.episode_id}?#{query}")
      render_async(invalid)
      assert has_element?(invalid, "#episode-error")
      refute has_element?(invalid, "#episode-video-frame[data-src]")
    end
  end

  test "a transcoded part releases its session before opening the next part", ctx do
    first = add_part(ctx, 1)
    add_part(ctx, 2)
    executable = Path.join(ctx.directory, "part-ffmpeg")
    File.write!(executable, "#!/bin/sh\nwhile :; do sleep 1; done\n")
    File.chmod!(executable, 0o700)
    old = Application.get_env(:bolognesa, :ffmpeg_executable)
    Application.put_env(:bolognesa, :ffmpeg_executable, executable)

    on_exit(fn ->
      TranscodeManager.stop_all()

      if old,
        do: Application.put_env(:bolognesa, :ffmpeg_executable, old),
        else: Application.delete_env(:bolognesa, :ffmpeg_executable)
    end)

    {:ok, view, _} = live(ctx.conn, "/episodes/#{ctx.episode_id}?part=1")
    render_async(view)
    html = render_hook(view, "playback_error", %{file_id: to_string(first.id)})
    [_, session] = Regex.run(~r/data-session-id="([^"]+)"/, html)
    render_hook(view, "playback_ended", %{session_id: session})
    render_async(view)
    assert_patch(view, "/episodes/#{ctx.episode_id}?part=2")
    assert :not_found = Bolognesa.Playback.video_transcode_status(session)
  end

  test "a playback error keeps the player mounted for retry", ctx do
    {:ok, view, _} = live(ctx.conn, "/episodes/#{ctx.episode_id}")
    render_async(view)
    File.rm!(Path.join(ctx.directory, ctx.media_file.relative_path))
    render_hook(view, "playback_error", %{file_id: to_string(ctx.media_file.id)})
    assert has_element?(view, "#episode-playback-error")
    assert has_element?(view, "#episode-video-frame[phx-hook='VideoPlayer'][data-playback-error]")
    refute has_element?(view, "#episode-video-frame[data-src]")
    assert has_element?(view, "#episode-retry-playback")
  end

  test "failed episode navigation releases conversion and cannot reuse the previous detail",
       ctx do
    executable = Path.join(ctx.directory, "navigation-ffmpeg")
    File.write!(executable, "#!/bin/sh\nwhile :; do sleep 1; done\n")
    File.chmod!(executable, 0o700)
    old = Application.get_env(:bolognesa, :ffmpeg_executable)
    Application.put_env(:bolognesa, :ffmpeg_executable, executable)

    on_exit(fn ->
      TranscodeManager.stop_all()

      if old,
        do: Application.put_env(:bolognesa, :ffmpeg_executable, old),
        else: Application.delete_env(:bolognesa, :ffmpeg_executable)
    end)

    {:ok, view, _} = live(ctx.conn, "/episodes/#{ctx.episode_id}")
    render_async(view)
    html = render_hook(view, "playback_error", %{file_id: to_string(ctx.media_file.id)})
    [_, session] = Regex.run(~r/data-session-id="([^"]+)"/, html)
    render_patch(view, "/episodes/0")
    render_async(view)
    assert has_element?(view, "#episode-error")
    refute has_element?(view, "#episode-title")
    assert :not_found = Bolognesa.Playback.video_transcode_status(session)
    render_patch(view, "/episodes/0?part=1")
    assert has_element?(view, "#episode-error")
    refute has_element?(view, "#episode-video-frame")
  end

  test "compact heading and localized air date below the synopsis", ctx do
    alias Bolognesa.Infrastructure.Persistence.EpisodeSchema

    Bolognesa.Repo.get!(EpisodeSchema, ctx.episode_id)
    |> Ecto.Changeset.change(air_date: ~D[2008-01-20])
    |> Bolognesa.Repo.update!()

    {:ok, view, _} = live(ctx.conn, "/episodes/#{ctx.episode_id}")
    render_async(view)
    assert has_element?(view, "#episode-breadcrumb #episode-series")
    assert has_element?(view, "#episode-breadcrumb #episode-season", "Especiales")

    assert has_element?(
             view,
             "#episode-synopsis #episode-air-date time[datetime='2008-01-20']",
             "20 ene 2008"
           )

    assert has_element?(view, "#episode-air-date [aria-hidden='true'] .hero-calendar-days")

    refute has_element?(view, ".episode-heading time")
    refute has_element?(view, ".episode-heading", "Serie")
  end

  test "manual navigation follows same-season order, including unavailable episodes", ctx do
    [first, last] = ctx.episode_ids
    other = Bolognesa.SeriesFixtures.file(ctx.library.id, "other-season.mp4")
    Bolognesa.SeriesFixtures.identify(other, 1, [1])

    Bolognesa.Repo.get_by!(Bolognesa.Infrastructure.Persistence.SeriesIdentificationEpisodeSchema,
      episode_id: last
    )
    |> Bolognesa.Repo.delete!()

    {:ok, view, _} = live(ctx.conn, "/episodes/#{first}?season_page=3")
    render_async(view)
    refute has_element?(view, "#episode-previous")

    assert has_element?(
             view,
             "#episode-player + #episode-navigation #episode-next[href='/episodes/#{last}?season_page=3'][data-phx-link='patch']"
           )

    assert has_element?(view, "#episode-next", "Siguiente")

    view |> element("#episode-next") |> render_click()
    render_async(view)
    next_view = view
    assert has_element?(next_view, "#episode-previous[href='/episodes/#{first}?season_page=3']")
    refute has_element?(next_view, "#episode-next")
    refute has_element?(next_view, "#episode-air-date")
  end

  test "direct delivery checks each episode association and supports ranges", ctx do
    for id <- ctx.episode_ids do
      conn =
        ctx.conn
        |> put_req_header("range", "bytes=2-4")
        |> get("/episodes/#{id}/media/#{ctx.media_file.id}")

      assert response(conn, 206) == "cde"
    end

    conn = get(ctx.conn, "/episodes/#{Enum.max(ctx.episode_ids) + 1}/media/#{ctx.media_file.id}")
    assert response(conn, 404) == ""

    conn =
      get(Phoenix.ConnTest.build_conn(), "/episodes/#{ctx.episode_id}/media/#{ctx.media_file.id}")

    assert response(conn, 401) == ""
  end

  test "defaults to the first version and still allows switching versions", ctx do
    second = add_version(ctx)
    {:ok, view, _} = live(ctx.conn, "/episodes/#{ctx.episode_id}")
    render_async(view)

    assert has_element?(
             view,
             "#episode-video-frame[data-video-id='episode-video-#{ctx.media_file.id}']"
           )

    view |> element("#episode-play-#{second.id}") |> render_click()
    assert has_element?(view, "#episode-video-frame[data-video-id='episode-video-#{second.id}']")
    assert has_element?(view, "#episode-selected-#{second.id}")
    refute has_element?(view, "#episode-selected-#{ctx.media_file.id}")
    assert has_element?(view, "#episode-play-#{ctx.media_file.id}")
  end

  test "skips unavailable versions when loading the episode", ctx do
    second = add_version(ctx)
    mark_unavailable(ctx.media_file)
    {:ok, view, _} = live(ctx.conn, "/episodes/#{ctx.episode_id}")
    render_async(view)

    assert has_element?(view, "#episode-video-frame[data-video-id='episode-video-#{second.id}']")
    refute has_element?(view, "#episode-playback-error")
  end

  test "leaves the player empty when no version is available", ctx do
    mark_unavailable(ctx.media_file)
    {:ok, view, _} = live(ctx.conn, "/episodes/#{ctx.episode_id}")
    render_async(view)

    assert has_element?(view, "#episode-title")
    refute has_element?(view, "#episode-player")
    refute has_element?(view, "#episode-playback-error")
    assert has_element?(view, "#episode-unavailable", "No disponible")
  end

  test "playback precedes the synopsis and technical options start collapsed", ctx do
    {:ok, view, _} = live(ctx.conn, "/episodes/#{ctx.episode_id}")
    render_async(view)
    assert has_element?(view, "#episode-player ~ #episode-synopsis")
    assert has_element?(view, "details#episode-playback-options:not([open]) #episode-versions")
    refute has_element?(view, "#episode-player h2", "versión")
    refute has_element?(view, "#episode-play-#{ctx.media_file.id}")
    assert has_element?(view, "#episode-selected-#{ctx.media_file.id}")
  end

  test "contextual return preserves catalog search and season page", ctx do
    {:ok, view, _} =
      live(
        ctx.conn,
        "/episodes/#{ctx.episode_id}?library_id=#{ctx.library.id}&catalog_query=Serie&catalog_page=2&season_page=3"
      )

    render_async(view)

    assert has_element?(
             view,
             "#episode-back[href='/series/seasons/#{ctx.season_id}?catalog_page=2&catalog_query=Serie&library_id=#{ctx.library.id}&page=3']"
           )

    assert has_element?(
             view,
             "#episode-series[href='/series/#{ctx.series_id}?catalog_page=2&catalog_query=Serie&library_id=#{ctx.library.id}']"
           )
  end

  test "malformed return context is ignored", ctx do
    {:ok, view, _} =
      live(
        ctx.conn,
        "/episodes/#{ctx.episode_id}?catalog_query[]=bad&catalog_page[]=1&season_page=invalid"
      )

    render_async(view)
    assert has_element?(view, "#episode-back[href='/series/seasons/#{ctx.season_id}']")
    assert has_element?(view, "#episode-series[href='/series/#{ctx.series_id}']")
  end

  test "finishing direct playback advances past episodes sharing the file", ctx do
    next_file = add_playable_file(ctx, "next.mp4")

    next =
      Bolognesa.SeriesFixtures.identify(next_file, 1, [1]) |> Map.fetch!(:episode_ids) |> hd()

    {:ok, view, _} = live(ctx.conn, "/episodes/#{ctx.episode_id}")
    render_async(view)
    render_hook(view, "playback_ended", %{file_id: to_string(ctx.media_file.id)})
    render_async(view)
    assert_patch(view, "/episodes/#{next}")
    render_async(view)

    assert has_element?(
             view,
             "#episode-video-frame[data-src='/episodes/#{next}/media/#{next_file.id}']"
           )
  end

  test "same-season automatic advance preserves the season return page", ctx do
    Bolognesa.SeriesFixtures.identify(ctx.media_file, 0, [1])
    file = add_playable_file(ctx, "next-same-season.mp4")
    next = Bolognesa.SeriesFixtures.identify(file, 0, [2]) |> Map.fetch!(:episode_ids) |> hd()
    {:ok, view, _} = live(ctx.conn, "/episodes/#{ctx.episode_id}?season_page=3")
    render_async(view)
    render_hook(view, "playback_ended", %{file_id: to_string(ctx.media_file.id)})
    render_async(view)
    assert_patch(view, "/episodes/#{next}?season_page=3")
  end

  test "initial preparation failure keeps a visible retry without claiming no versions exist",
       ctx do
    File.rm!(Path.join(ctx.directory, ctx.media_file.relative_path))
    {:ok, view, _} = live(ctx.conn, "/episodes/#{ctx.episode_id}")
    render_async(view)
    assert has_element?(view, "#episode-playback-error")
    refute has_element?(view, "#episode-unavailable")
    assert has_element?(view, "#episode-retry-playback[phx-value-file_id='#{ctx.media_file.id}']")
  end

  test "finishing transcode playback advances and releases the session", ctx do
    executable = Path.join(ctx.directory, "fake-ffmpeg")
    File.write!(executable, "#!/bin/sh\nwhile :; do sleep 1; done\n")
    File.chmod!(executable, 0o700)
    old = Application.get_env(:bolognesa, :ffmpeg_executable)
    Application.put_env(:bolognesa, :ffmpeg_executable, executable)

    on_exit(fn ->
      TranscodeManager.stop_all()

      if old,
        do: Application.put_env(:bolognesa, :ffmpeg_executable, old),
        else: Application.delete_env(:bolognesa, :ffmpeg_executable)
    end)

    next_file = add_playable_file(ctx, "next.mp4")

    next =
      Bolognesa.SeriesFixtures.identify(next_file, 1, [1]) |> Map.fetch!(:episode_ids) |> hd()

    {:ok, view, _} = live(ctx.conn, "/episodes/#{ctx.episode_id}")
    render_async(view)
    html = render_hook(view, "playback_error", %{file_id: to_string(ctx.media_file.id)})
    [_, session] = Regex.run(~r/data-session-id="([^"]+)"/, html)
    render_hook(view, "playback_ended", %{session_id: session})
    render_async(view)
    assert_patch(view, "/episodes/#{next}")
    render_async(view)

    assert has_element?(
             view,
             "#episode-video-frame[data-src='/episodes/#{next}/media/#{next_file.id}']"
           )

    assert :not_found = Bolognesa.Playback.video_transcode_status(session)
  end

  test "stale completion and the final episode do not navigate", ctx do
    {:ok, view, _} = live(ctx.conn, "/episodes/#{ctx.episode_id}")
    render_async(view)
    render_hook(view, "playback_ended", %{file_id: "0"})
    render_hook(view, "playback_ended", %{session_id: "stale"})
    render_hook(view, "playback_ended", %{file_id: to_string(ctx.media_file.id)})
    render_async(view)
    assert has_element?(view, "#episode-title")
  end

  defp add_version(ctx) do
    name = "Second S00E01E02.mp4"

    File.cp!(
      Path.join(ctx.directory, ctx.media_file.relative_path),
      Path.join(ctx.directory, name)
    )

    {:ok, stat} = File.stat(Path.join(ctx.directory, name), time: :posix)

    file =
      ctx.media_file
      |> Map.from_struct()
      |> Map.drop([:__meta__, :id, :inserted_at, :updated_at])
      |> Map.put(:relative_path, name)
      |> Map.put(:modified_at, DateTime.from_unix!(stat.mtime * 1_000_000, :microsecond))
      |> then(&struct!(Bolognesa.Infrastructure.Persistence.MediaFileSchema, &1))
      |> Bolognesa.Repo.insert!()

    Bolognesa.SeriesFixtures.identify(file, 0, [1, 2])
    file
  end

  defp add_part(ctx, part) do
    file = add_playable_file(ctx, "Example S00E01-part#{part}.mp4")
    Bolognesa.SeriesFixtures.identify(file, 0, [1])
    file
  end

  defp add_playable_file(ctx, name) do
    path = Path.join(ctx.directory, name)
    File.cp!(Path.join(ctx.directory, ctx.media_file.relative_path), path)
    stat = File.stat!(path, time: :posix)
    file = Bolognesa.SeriesFixtures.file(ctx.library.id, name)

    file
    |> Ecto.Changeset.change(
      modified_at: DateTime.from_unix!(stat.mtime * 1_000_000, :microsecond)
    )
    |> Bolognesa.Repo.update!()
  end

  defp mark_unavailable(file) do
    file
    |> Ecto.Changeset.change(availability: :missing)
    |> Bolognesa.Repo.update!()
  end
end
