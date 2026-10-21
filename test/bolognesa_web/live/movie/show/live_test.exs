defmodule BolognesaWeb.Movie.Show.LiveTest do
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Bolognesa.Accounts
  alias Bolognesa.Infrastructure.LocalSourcePath
  alias Bolognesa.Infrastructure.Persistence.InspectionSchema
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.MovieSchema
  alias Bolognesa.Playback.Infrastructure.TranscodeManager
  alias Bolognesa.Repo

  test "shows movie details and versions container", %{conn: conn} do
    {:ok, _} =
      Accounts.install_admin(%{
        name: "Ada",
        email: "show@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} = Accounts.start_session("show@example.com", "correct horse battery staple")

    movie =
      Repo.insert!(
        movie_changeset(%{
          provider: :tmdb,
          provider_id: 999,
          title: "Mi pelicula"
        })
      )

    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/movies/#{movie.id}")
    render_async(view)
    assert has_element?(view, "#movie-versions")
    assert has_element?(view, "#movie-title", "Mi pelicula")
    refute has_element?(view, "#movie-player")
    refute has_element?(view, "#movie-playback-error")
  end

  test "each confirmed version can open manual correction", %{conn: conn} do
    {:ok, _} =
      Accounts.install_admin(%{
        name: "Ada",
        email: "correct-show@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} =
      Accounts.start_session("correct-show@example.com", "correct horse battery staple")

    movie =
      Repo.insert!(
        movie_changeset(%{
          provider: :tmdb,
          provider_id: 1000,
          title: "Mi pelicula"
        })
      )

    library =
      Repo.insert!(LibrarySchema.changeset(%LibrarySchema{}, %{name: "Show", path: "/show"}))

    file =
      Repo.insert!(
        MediaFileSchema.changeset(%MediaFileSchema{}, %{
          library_id: library.id,
          relative_path: "Film.mkv",
          size_bytes: 1,
          modified_at: DateTime.utc_now(),
          last_seen_generation: Ecto.UUID.generate()
        })
      )

    Bolognesa.MovieIdentificationFixtures.insert_decision!(
      %{
        media_file_id: file.id,
        observed_revision: 1,
        token: Ecto.UUID.generate(),
        state: :automatic,
        origin: :automatic
      },
      movie.id
    )

    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/movies/#{movie.id}")
    render_async(view)

    assert has_element?(
             view,
             "#movie-correct-#{file.id}[href='/movies/review?file_id=#{file.id}']"
           )
  end

  describe "video playback" do
    setup %{conn: conn} do
      {:ok, _} =
        Accounts.install_admin(%{
          name: "Ada",
          email: "play-show@example.com",
          password: "correct horse battery staple"
        })

      {:ok, token} =
        Accounts.start_session("play-show@example.com", "correct horse battery staple")

      movie =
        Repo.insert!(
          movie_changeset(%{
            provider: :tmdb,
            provider_id: 1001,
            title: "Mi pelicula"
          })
        )

      base = hd(Application.fetch_env!(:bolognesa, :library_roots))
      directory = Path.join(base, "play-show-#{System.unique_integer([:positive])}")
      File.mkdir_p!(directory)
      on_exit(fn -> File.rm_rf!(directory) end)
      {:ok, physical} = LocalSourcePath.canonical_directory(directory)
      File.write!(Path.join(physical, "first.mp4"), "abcdefgh")
      File.write!(Path.join(physical, "second.mkv"), "abcdefgh")

      library =
        Repo.insert!(LibrarySchema.changeset(%LibrarySchema{}, %{name: "Play", path: physical}))

      first = insert_version(library.id, movie.id, physical, "first.mp4", :available)
      second = insert_version(library.id, movie.id, physical, "second.mkv", :available)
      missing = insert_version(library.id, movie.id, physical, "missing.mp4", :missing)

      executable = Path.join(physical, "fake-ffmpeg")
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

      {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/movies/#{movie.id}")
      render_async(view)

      %{
        conn: init_test_session(conn, user_token: token),
        view: view,
        movie: movie,
        first: first,
        second: second,
        missing: missing,
        directory: physical
      }
    end

    test "loads the first available version and allows switching while ignoring stale errors",
         ctx do
      %{view: view, movie: movie, first: first, second: second, missing: missing} = ctx
      assert has_element?(view, "#movie-play-#{first.id}")
      assert has_element?(view, "#movie-play-#{second.id}")
      refute has_element?(view, "#movie-play-#{missing.id}")

      assert has_element?(
               view,
               "#movie-video-frame[data-autoplay='true'][data-src='/movies/#{movie.id}/media/#{first.id}']"
             )

      render_click(element(view, "#movie-play-#{second.id}"))
      render_hook(view, "playback_error", %{"file_id" => Integer.to_string(first.id)})

      assert has_element?(
               view,
               "#movie-video-frame[data-src='/movies/#{movie.id}/media/#{second.id}']"
             )

      refute has_element?(view, "#movie-video-frame[data-video-id='movie-video-#{first.id}']")
      refute has_element?(view, "#movie-playback-error")
      refute has_element?(view, "#movie-playback-preparing")
    end

    test "skips unavailable versions when opening the movie", ctx do
      mark_unavailable(ctx.first)
      {:ok, view, _} = live(ctx.conn, ~p"/movies/#{ctx.movie.id}")
      render_async(view)

      assert has_element?(
               view,
               "#movie-video-frame[data-video-id='movie-video-#{ctx.second.id}']"
             )

      refute has_element?(view, "#movie-playback-error")
    end

    test "leaves the player empty when every version is unavailable", ctx do
      mark_unavailable(ctx.first)
      mark_unavailable(ctx.second)
      {:ok, view, _} = live(ctx.conn, ~p"/movies/#{ctx.movie.id}")
      render_async(view)

      assert has_element?(view, "#movie-title")
      refute has_element?(view, "#movie-player")
      refute has_element?(view, "#movie-playback-error")
    end

    test "automatically selected compatible delivery requests autoplay when ready", ctx do
      insert_incompatible_inspection(ctx.first)
      {:ok, view, _} = live(ctx.conn, ~p"/movies/#{ctx.movie.id}")
      render_async(view)
      session = preparing_session(view)
      make_ready(view, session)

      assert has_element?(
               view,
               "#movie-video-frame[data-video-id='movie-video-#{session.id}'][data-autoplay='true']"
             )
    end

    test "automatically converts a browser failure at its position without duplicate starts",
         ctx do
      %{view: view, first: first} = ctx
      render_click(element(view, "#movie-play-#{first.id}"))

      render_hook(view, "playback_error", %{
        "file_id" => Integer.to_string(first.id),
        "position_ms" => "12000"
      })

      session = preparing_session(view)
      assert session.profile == :video
      assert session.offset_ms == 12_000
      refute has_element?(view, "#movie-playback-error")
      render_hook(view, "playback_error", %{"file_id" => Integer.to_string(first.id)})
      assert has_element?(view, "#movie-playback-preparing[data-session-id='#{session.id}']")
    end

    test "selecting a direct version releases the previous conversion", ctx do
      watch_closures()
      session = start_inspected_version(ctx)
      render_click(element(ctx.view, "#movie-play-#{ctx.first.id}"))
      assert_receive {:session_closed, %{session_id: closed_id, reason: :version_selected}}
      assert closed_id == session.id
      assert {:error, :not_found} = TranscodeManager.lookup(session.id)

      assert has_element?(
               ctx.view,
               "#movie-video-frame[data-video-id='movie-video-#{ctx.first.id}']"
             )

      refute has_element?(ctx.view, "#movie-playback-preparing")
    end

    test "prepares inspected incompatible media and displays its HLS controls when ready", ctx do
      session = start_inspected_version(ctx)
      assert session.profile == :audio
      assert has_element?(ctx.view, "#movie-playback-preparing", "Preparando versión compatible")
      refute has_element?(ctx.view, "#movie-video-frame[data-src]")
      make_ready(ctx.view, session)

      assert has_element?(
               ctx.view,
               "#movie-video-frame[data-video-id='movie-video-#{session.id}'][data-src$='/index.m3u8']"
             )

      assert has_element?(
               ctx.view,
               "#movie-video-frame[phx-hook='VideoPlayer'] #movie-video-ui[phx-update='ignore'] video"
             )

      refute has_element?(ctx.view, "input[data-compatible-seek]")
      refute has_element?(ctx.view, "#movie-playback-preparing")
    end

    test "pauses and resumes the displayed compatible session", ctx do
      session = start_inspected_version(ctx)
      make_ready(ctx.view, session)
      render_hook(ctx.view, "playback_pause", %{"session_id" => session.id})
      assert {:ok, _} = TranscodeManager.lookup(session.id)

      assert has_element?(
               ctx.view,
               "#movie-video-frame[data-video-id='movie-video-#{session.id}'][data-paused-server='true']"
             )

      render_hook(ctx.view, "playback_resume", %{
        "session_id" => session.id,
        "position_ms" => "1000"
      })

      assert has_element?(
               ctx.view,
               "#movie-video-frame[data-video-id='movie-video-#{session.id}'][data-paused-server='false']"
             )
    end

    test "seeking replaces the compatible session and rejects malformed positions", ctx do
      watch_closures()
      session = start_inspected_version(ctx)
      make_ready(ctx.view, session)
      render_hook(ctx.view, "playback_seek", %{"session_id" => session.id, "position_ms" => 1000})

      assert has_element?(
               ctx.view,
               "#movie-video-frame[data-video-id='movie-video-#{session.id}']"
             )

      render_hook(ctx.view, "playback_seek", %{
        "session_id" => session.id,
        "position_ms" => "10000",
        "playing" => "true"
      })

      next = preparing_session(ctx.view)
      assert_receive {:session_closed, %{session_id: closed_id, reason: :seek}}
      assert closed_id == session.id
      assert next.id != session.id
      assert next.offset_ms == 10_000
      assert next.profile == :audio
      assert {:error, :not_found} = TranscodeManager.lookup(session.id)
      make_ready(ctx.view, next)

      assert has_element?(
               ctx.view,
               "#movie-video-frame[data-video-id='movie-video-#{next.id}'][data-autoplay='true']"
             )
    end

    test "conversion failure stays visible until an explicit retry", ctx do
      %{view: view, first: first} = ctx
      render_click(element(view, "#movie-play-#{first.id}"))
      render_hook(view, "playback_error", %{"file_id" => Integer.to_string(first.id)})
      session = preparing_session(view)
      render_hook(view, "compatible_error", %{"session_id" => session.id})
      assert has_element?(view, "#movie-playback-error[data-reason='transcode_failed']")
      render_hook(view, "playback_error", %{"file_id" => Integer.to_string(first.id)})
      assert has_element?(view, "#movie-playback-error[data-reason='transcode_failed']")
      assert {:error, :not_found} = TranscodeManager.lookup(session.id)
      render_hook(view, "playback_seek", %{"session_id" => session.id, "position_ms" => "1000"})
      next = preparing_session(view)
      assert next.profile == :video
      assert next.offset_ms == 1_000
      refute has_element?(view, "#movie-playback-error")
    end

    test "failed fallback preparation removes the failed player and does not loop", ctx do
      %{view: view, first: first} = ctx
      render_click(element(view, "#movie-play-#{first.id}"))
      File.rm!(Path.join(ctx.directory, "first.mp4"))
      render_hook(view, "playback_error", %{"file_id" => Integer.to_string(first.id)})
      assert has_element?(view, "#movie-playback-error[data-reason='file_unavailable']")
      render_hook(view, "playback_error", %{"file_id" => Integer.to_string(first.id)})
      assert has_element?(view, "#movie-playback-error[data-reason='file_unavailable']")
      refute has_element?(view, "#movie-playback-preparing")
      refute has_element?(view, "#movie-player video")
      render_click(element(view, "#movie-play-#{ctx.second.id}"))

      assert has_element?(
               view,
               "#movie-video-frame[data-video-id='movie-video-#{ctx.second.id}']"
             )

      refute has_element?(view, "#movie-playback-error")
    end

    test "shows the first selection error when the file has disappeared", ctx do
      File.rm!(Path.join(ctx.directory, "first.mp4"))
      render_click(element(ctx.view, "#movie-play-#{ctx.first.id}"))
      assert has_element?(ctx.view, "#movie-playback-error[data-reason='file_unavailable']")
      refute has_element?(ctx.view, "#movie-player video")
    end
  end

  defp start_inspected_version(ctx) do
    insert_incompatible_inspection(ctx.second)
    render_click(element(ctx.view, "#movie-play-#{ctx.second.id}"))
    preparing_session(ctx.view)
  end

  defp insert_incompatible_inspection(file) do
    Repo.insert!(
      InspectionSchema.changeset(%InspectionSchema{}, %{
        media_file_id: file.id,
        token: Ecto.UUID.generate(),
        observed_revision: file.revision,
        state: :succeeded,
        format: "matroska,webm",
        duration_ms: 60_000,
        tracks: %{
          "items" => [
            %{"kind" => "video", "codec" => "h264"},
            %{"kind" => "audio", "codec" => "ac3"}
          ]
        }
      })
    )
  end

  defp preparing_session(view) do
    [_, id] =
      Regex.run(~r/id="movie-playback-preparing"[^>]*data-session-id="([^"]+)"/, render(view))

    {:ok, session} = TranscodeManager.lookup(id)
    session
  end

  defp make_ready(view, session) do
    File.write!(Path.join(session.directory, "seg-000000.ts"), "segment")

    File.write!(
      Path.join(session.directory, "index.m3u8"),
      "#EXTM3U\n#EXTINF:4.0,\nseg-000000.ts\n"
    )

    send(view.pid, {:compatible_poll, session.id})
  end

  defp insert_version(library_id, movie_id, directory, path, availability) do
    physical_path = Path.join(directory, path)

    modified_at =
      if availability == :available do
        {:ok, stat} = File.lstat(physical_path, time: :posix)
        DateTime.from_unix!(stat.mtime * 1_000_000, :microsecond)
      else
        DateTime.utc_now()
      end

    file =
      Repo.insert!(
        MediaFileSchema.changeset(%MediaFileSchema{}, %{
          library_id: library_id,
          relative_path: path,
          size_bytes: 8,
          modified_at: modified_at,
          availability: availability,
          last_seen_generation: Ecto.UUID.generate()
        })
      )

    Bolognesa.MovieIdentificationFixtures.insert_decision!(
      %{
        media_file_id: file.id,
        observed_revision: 1,
        token: Ecto.UUID.generate(),
        state: :automatic,
        origin: :automatic
      },
      movie_id
    )

    file
  end

  defp watch_closures do
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:bolognesa, :playback, :session, :closed],
        &__MODULE__.handle_session_closed/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  @spec handle_session_closed([atom()], map(), map(), pid()) :: any()
  def handle_session_closed(_event, _measurements, metadata, caller),
    do: send(caller, {:session_closed, metadata})

  defp movie_changeset(attrs),
    do: MovieSchema.changeset(%MovieSchema{}, Map.put_new(attrs, :provider, :tmdb))

  defp mark_unavailable(file) do
    file
    |> Ecto.Changeset.change(availability: :missing)
    |> Repo.update!()
  end
end
