defmodule BolognesaWeb.Movie.Show.LiveTest do
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  import Bolognesa.PlaybackNegotiationFixtures,
    only: [inspect!: 1, inspect!: 3, negotiate: 1, report: 1]

  alias Bolognesa.Accounts
  alias Bolognesa.Infrastructure.LocalSourcePath
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
          title: "Mi pelicula",
          overview: "Una historia para descubrir."
        })
      )

    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/movies/#{movie.id}")
    render_async(view)
    assert has_element?(view, "#movie-playback-options:not([open]) #movie-versions")

    assert has_element?(
             view,
             "#movie-description:not([open]) summary",
             "Una historia para descubrir."
           )

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
    setup %{conn: conn} = context do
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
      inspect!(first)
      inspect!(second)
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

      unless context[:checking], do: negotiate(view)

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

    @tag :checking
    test "checking withholds delivery and rejects stale malformed and duplicate reports", ctx do
      view = ctx.view

      assert has_element?(
               view,
               "#movie-video-frame[data-playback-phase='checking']:not([data-src]) video:not([src]):not([autoplay])"
             )

      assert has_element?(view, "#movie-playback-checking")
      old = report(view)
      render_hook(view, "playback_capabilities", Map.put(old, "version", 99))
      assert has_element?(view, "#movie-playback-checking")
      render_click(element(view, "#movie-play-#{ctx.second.id}"))
      render_hook(view, "playback_capabilities", old)
      assert has_element?(view, "#movie-playback-checking")
      fresh = report(view)
      render_hook(view, "playback_capabilities", fresh)

      assert has_element?(
               view,
               "#movie-video-frame[data-src='/movies/#{ctx.movie.id}/media/#{ctx.second.id}']"
             )

      render_hook(view, "playback_capabilities", fresh)
      refute has_element?(view, "#movie-video-frame[data-session-id]")
    end

    @tag :checking
    test "unknown detection stays terminal until explicit original playback", ctx do
      raw = report(ctx.view)

      raw =
        Map.update!(
          raw,
          "results",
          &Enum.map(&1, fn result -> Map.put(result, "support", "unknown") end)
        )

      render_hook(ctx.view, "playback_capabilities", raw)
      assert has_element?(ctx.view, "#movie-playback-error")
      refute has_element?(ctx.view, "#movie-video-frame[data-src]")
      refute has_element?(ctx.view, "#movie-video-frame[data-session-id]")
      render_hook(ctx.view, "playback_original", %{})

      assert has_element?(
               ctx.view,
               "#movie-video-frame[data-src='/movies/#{ctx.movie.id}/media/#{ctx.first.id}']"
             )
    end

    @tag :checking
    test "a missing capability report times out without opening the original", ctx do
      send(ctx.view.pid, {:capability_timeout, report(ctx.view)["generation"]})
      assert has_element?(ctx.view, "#movie-playback-error")
      refute has_element?(ctx.view, "#movie-video-frame[data-src]")
    end

    @tag :checking
    test "explicit inspection refresh is authorized and can be requested once per action", ctx do
      inspection =
        Repo.get_by!(Bolognesa.Infrastructure.Persistence.InspectionSchema,
          media_file_id: ctx.first.id
        )

      inspection
      |> Ecto.Changeset.change(updated_at: DateTime.add(DateTime.utc_now(), -31, :second))
      |> Repo.update!()

      send(ctx.view.pid, {:capability_timeout, report(ctx.view)["generation"]})
      assert has_element?(ctx.view, "#movie-playback-error")
      render_hook(ctx.view, "playback_refresh", %{})
      requested = Repo.get!(Bolognesa.Infrastructure.Persistence.InspectionSchema, inspection.id)
      assert requested.state == :pending
      assert has_element?(ctx.view, "[role='status']", "Análisis solicitado")
      render_hook(ctx.view, "playback_refresh", %{})

      assert Repo.get!(Bolognesa.Infrastructure.Persistence.InspectionSchema, inspection.id).token ==
               requested.token

      refute has_element?(ctx.view, "#movie-video-frame[data-src]")
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

      assert has_element?(view, "#playback-mode", "Reproducción directa")

      assert has_element?(view, "#movie-selected-#{first.id}", "Seleccionada")
      render_click(element(view, "#movie-play-#{second.id}"))
      if has_element?(view, "[data-playback-probe]"), do: negotiate(view)
      assert has_element?(view, "#movie-selected-#{second.id}", "Seleccionada")
      refute has_element?(view, "#movie-selected-#{first.id}")
      playback_error(view, %{"file_id" => Integer.to_string(first.id)})

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

    test "automatically selected transcode delivery requests autoplay when ready", ctx do
      insert_incompatible_inspection(ctx.first)
      {:ok, view, _} = live(ctx.conn, ~p"/movies/#{ctx.movie.id}")
      render_async(view)
      negotiate(view)
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
      if has_element?(view, "[data-playback-probe]"), do: negotiate(view)

      playback_error(view, %{
        "file_id" => Integer.to_string(first.id),
        "position_ms" => "12000"
      })

      session = preparing_session(view)
      assert session.strategy == :full_conversion
      assert has_element?(view, "#playback-mode", "Transcodificación de vídeo y audio")
      assert session.offset_ms == 12_000
      refute has_element?(view, "#movie-playback-error")
      playback_error(view, %{"file_id" => Integer.to_string(first.id)})
      assert has_element?(view, "#movie-playback-preparing")
    end

    test "negotiation authorizes issuance and reauthorizes selection and delivery", ctx do
      insert_incompatible_inspection(ctx.second)
      handler = {__MODULE__, make_ref()}
      caller = self()

      :ok =
        :telemetry.attach(
          handler,
          [:bolognesa, :repo, :query],
          fn _event, _measurements, metadata, {recipient, view_pid} ->
            if self() == view_pid and String.contains?(metadata.query, "movie_identifications") and
                 String.contains?(metadata.query, "inspections") do
              send(recipient, :playback_source_selected)
            end
          end,
          {caller, ctx.view.pid}
        )

      on_exit(fn -> :telemetry.detach(handler) end)

      for file <- [ctx.first, ctx.second] do
        render_click(element(ctx.view, "#movie-play-#{file.id}"))
        if has_element?(ctx.view, "[data-playback-probe]"), do: negotiate(ctx.view)
        assert_receive :playback_source_selected
        assert_receive :playback_source_selected
        assert_receive :playback_source_selected
        refute_receive :playback_source_selected
      end

      assert has_element?(ctx.view, "#movie-playback-preparing")
    end

    test "selecting a direct version releases the previous conversion", ctx do
      watch_closures()
      session = start_inspected_version(ctx)
      render_click(element(ctx.view, "#movie-play-#{ctx.first.id}"))
      if has_element?(ctx.view, "[data-playback-probe]"), do: negotiate(ctx.view)
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
      assert session.strategy == :audio_conversion
      assert has_element?(ctx.view, "#movie-playback-preparing")
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

      refute has_element?(ctx.view, "input[data-transcode-seek]")
      refute has_element?(ctx.view, "#movie-playback-preparing")
    end

    test "pauses and resumes the displayed transcode session", ctx do
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

      # A previously scheduled preparation poll can arrive after playback resumes.
      send(ctx.view.pid, {:transcode_poll, session.id})

      assert has_element?(
               ctx.view,
               "#movie-video-frame[data-video-id='movie-video-#{session.id}'][data-paused-server='false']"
             )
    end

    test "seeking replaces the transcode session and rejects malformed positions", ctx do
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
      assert next.strategy == :audio_conversion
      assert {:error, :not_found} = TranscodeManager.lookup(session.id)
      make_ready(ctx.view, next)

      assert has_element?(
               ctx.view,
               "#movie-video-frame[data-video-id='movie-video-#{next.id}'][data-autoplay='true']"
             )
    end

    test "tab recovery uses an authorized whole-file offset and preserves pause", ctx do
      session = start_inspected_version(ctx)
      make_ready(ctx.view, session)

      render_hook(ctx.view, "playback_restore", %{
        "session_id" => session.id,
        "position_ms" => "10000",
        "playing" => "false"
      })

      next = preparing_session(ctx.view)
      assert next.id != session.id
      assert next.offset_ms == 10_000
      make_ready(ctx.view, next)

      assert has_element?(
               ctx.view,
               "#movie-video-frame[data-video-id='movie-video-#{next.id}'][data-autoplay='false']"
             )
    end

    test "failed seek retains the previous session for explicit cleanup", ctx do
      session = start_inspected_version(ctx)
      make_ready(ctx.view, session)

      Application.put_env(
        :bolognesa,
        :ffmpeg_executable,
        Path.join(ctx.directory, "missing-ffmpeg")
      )

      render_hook(ctx.view, "playback_seek", %{
        "session_id" => session.id,
        "position_ms" => "10000"
      })

      assert has_element?(ctx.view, "#movie-playback-error[data-reason='preparation_failed']")
      assert {:ok, ^session} = TranscodeManager.lookup(session.id)
      render_hook(ctx.view, "playback_ended", %{"session_id" => session.id})
      assert {:error, :not_found} = TranscodeManager.lookup(session.id)
    end

    test "rejects stale attempts and invalid recovery positions", ctx do
      %{view: view, first: first} = ctx
      old = playback_attempt(view)
      render_click(element(view, "#movie-play-#{first.id}"))
      negotiate(view)
      attempt = playback_attempt(view)
      refute attempt == old

      for {generation, position} <- [
            {old, "1000"},
            {attempt, "-1"},
            {attempt, "60001"},
            {attempt, "2147483648"}
          ] do
        playback_error(view, %{
          "file_id" => to_string(first.id),
          "attempt_id" => generation,
          "error_kind" => "media",
          "position_ms" => position
        })

        assert has_element?(view, "#movie-video-frame[data-playback-phase='ready']")
        refute has_element?(view, "#movie-playback-preparing")
      end
    end

    test "HDR original failure never starts an unsafe conversion", ctx do
      inspection = inspect!(ctx.first)

      tracks =
        update_in(inspection.tracks, ["items"], fn tracks ->
          Enum.map(tracks, fn
            %{"kind" => "video"} = video -> Map.put(video, "color_transfer", "smpte2084")
            track -> track
          end)
        end)

      Repo.update!(Ecto.Changeset.change(inspection, tracks: tracks))
      render_click(element(ctx.view, "#movie-play-#{ctx.first.id}"))
      negotiate(ctx.view)
      assert has_element?(ctx.view, "#movie-video-frame[data-playback-phase='ready']")
      playback_error(ctx.view, %{"file_id" => to_string(ctx.first.id)})
      assert has_element?(ctx.view, "#movie-playback-error")
      refute has_element?(ctx.view, "#movie-playback-preparing")
    end

    test "unknown compatible capability never triggers automatic conversion", ctx do
      render_click(element(ctx.view, "#movie-play-#{ctx.first.id}"))
      capability = report(ctx.view)

      results =
        Enum.map(capability["results"], fn result ->
          if result["candidate_id"] == "c0",
            do: result,
            else: Map.put(result, "support", "unknown")
        end)

      render_hook(ctx.view, "playback_capabilities", Map.put(capability, "results", results))
      playback_error(ctx.view, %{"file_id" => to_string(ctx.first.id)})
      assert has_element?(ctx.view, "#movie-playback-error")
      refute has_element?(ctx.view, "#movie-playback-preparing")
    end

    test "explicit original delivery ignores errors from its previous source", ctx do
      old = playback_attempt(ctx.view)
      render_hook(ctx.view, "playback_original", %{})
      refute playback_attempt(ctx.view) == old
      playback_error(ctx.view, %{"file_id" => to_string(ctx.first.id), "attempt_id" => old})
      refute has_element?(ctx.view, "#movie-playback-error")
      assert has_element?(ctx.view, "#movie-video-frame[data-playback-phase='ready']")
    end

    test "best-effort original does not inherit another version's duration", ctx do
      inspection =
        Repo.get_by!(Bolognesa.Infrastructure.Persistence.InspectionSchema,
          media_file_id: ctx.second.id
        )

      Repo.delete!(inspection)
      render_click(element(ctx.view, "#movie-play-#{ctx.second.id}"))
      assert has_element?(ctx.view, "#movie-playback-error")
      render_hook(ctx.view, "playback_original", %{})
      playback_error(ctx.view, %{"file_id" => to_string(ctx.second.id), "position_ms" => "60001"})
      assert has_element?(ctx.view, "#movie-playback-error")
      refute has_element?(ctx.view, "#movie-playback-preparing")
    end

    test "network failure never starts compatible conversion", ctx do
      playback_error(ctx.view, %{
        "file_id" => to_string(ctx.first.id),
        "attempt_id" => playback_attempt(ctx.view),
        "error_kind" => "network",
        "position_ms" => "1000"
      })

      assert has_element?(ctx.view, "#movie-playback-error")
      refute has_element?(ctx.view, "#movie-playback-preparing")
    end

    test "recovery budget survives seek and expired-session resume", ctx do
      %{view: view, first: first} = ctx
      attempt = playback_attempt(view)
      playback_error(view, %{"file_id" => to_string(first.id), "position_ms" => "1000"})
      recovered = preparing_session(view)
      make_ready(view, recovered)
      render_hook(view, "playback_seek", %{"session_id" => recovered.id, "position_ms" => "2000"})
      sought = preparing_session(view)
      make_ready(view, sought)
      assert playback_attempt(view) == attempt
      assert :ok = TranscodeManager.stop(sought.id, :client_error)
      render_hook(view, "playback_resume", %{"session_id" => sought.id, "position_ms" => "3000"})
      resumed = preparing_session(view)
      make_ready(view, resumed)
      assert playback_attempt(view) == attempt
      # Errors from the replaced session cannot spend or reset the budget.
      render_hook(view, "transcode_error", %{
        "session_id" => sought.id,
        "attempt_id" => attempt,
        "error_kind" => "media",
        "position_ms" => "3000"
      })

      refute has_element?(view, "#movie-playback-error")

      render_hook(view, "transcode_error", %{
        "session_id" => resumed.id,
        "attempt_id" => attempt,
        "error_kind" => "media",
        "position_ms" => "3000"
      })

      assert has_element?(view, "#movie-playback-error")
      refute has_element?(view, "#movie-playback-preparing")
      assert {:error, :not_found} = TranscodeManager.lookup(resumed.id)
    end

    test "failed compatible output never cycles to the original", ctx do
      render_click(element(ctx.view, "#movie-play-#{ctx.first.id}"))
      capability = report(ctx.view)

      render_hook(
        ctx.view,
        "playback_capabilities",
        Map.put(capability, "preference", "compatible")
      )

      session = preparing_session(ctx.view)
      make_ready(ctx.view, session)

      render_hook(ctx.view, "transcode_error", %{
        "session_id" => session.id,
        "attempt_id" => playback_attempt(ctx.view),
        "error_kind" => "media",
        "position_ms" => "0"
      })

      assert has_element?(ctx.view, "#movie-playback-error")
      refute has_element?(ctx.view, "#movie-video-frame[data-src]")
      assert {:error, :not_found} = TranscodeManager.lookup(session.id)
    end

    test "conversion failure stays visible until an explicit retry", ctx do
      %{view: view, first: first} = ctx
      render_click(element(view, "#movie-play-#{first.id}"))
      if has_element?(view, "[data-playback-probe]"), do: negotiate(view)
      playback_error(view, %{"file_id" => Integer.to_string(first.id)})
      session = preparing_session(view)
      make_ready(view, session)

      render_hook(view, "transcode_error", %{
        "session_id" => session.id,
        "attempt_id" => playback_attempt(view),
        "error_kind" => "media",
        "position_ms" => "1000"
      })

      assert has_element?(view, "#movie-playback-error[data-reason='transcode_failed']")
      playback_error(view, %{"file_id" => Integer.to_string(first.id)})
      assert has_element?(view, "#movie-playback-error[data-reason='transcode_failed']")
      assert {:error, :not_found} = TranscodeManager.lookup(session.id)
      render_hook(view, "playback_seek", %{"session_id" => session.id, "position_ms" => "1000"})
      assert has_element?(view, "#movie-playback-error[data-reason='transcode_failed']")
      refute has_element?(view, "#movie-playback-preparing")
      render_click(element(view, "#movie-retry-playback"))
      assert has_element?(view, "#movie-playback-checking")
    end

    test "failed fallback preparation keeps the player for retry and does not loop", ctx do
      %{view: view, first: first} = ctx
      render_click(element(view, "#movie-play-#{first.id}"))
      if has_element?(view, "[data-playback-probe]"), do: negotiate(view)
      File.rm!(Path.join(ctx.directory, "first.mp4"))
      playback_error(view, %{"file_id" => Integer.to_string(first.id)})
      assert has_element?(view, "#movie-playback-error[data-reason='file_unavailable']")
      assert has_element?(view, "#movie-retry-playback")
      playback_error(view, %{"file_id" => Integer.to_string(first.id)})
      assert has_element?(view, "#movie-playback-error[data-reason='file_unavailable']")
      refute has_element?(view, "#movie-playback-preparing")
      assert has_element?(view, "#movie-video-frame[data-playback-error]")
      refute has_element?(view, "#movie-video-frame[data-src]")
      render_click(element(view, "#movie-play-#{ctx.second.id}"))
      if has_element?(view, "[data-playback-probe]"), do: negotiate(view)

      assert has_element?(
               view,
               "#movie-video-frame[data-video-id='movie-video-#{ctx.second.id}']"
             )

      refute has_element?(view, "#movie-playback-error")
    end

    test "shows the first selection error when the file has disappeared", ctx do
      File.rm!(Path.join(ctx.directory, "first.mp4"))
      render_click(element(ctx.view, "#movie-play-#{ctx.first.id}"))
      if has_element?(ctx.view, "[data-playback-probe]"), do: negotiate(ctx.view)
      assert has_element?(ctx.view, "#movie-playback-error[data-reason='file_unavailable']")
      assert has_element?(ctx.view, "#movie-video-frame[data-playback-error]")
      refute has_element?(ctx.view, "#movie-video-frame[data-src]")
    end
  end

  defp playback_attempt(view) do
    render(view)
    |> LazyHTML.from_document()
    |> LazyHTML.query("#movie-video-frame")
    |> LazyHTML.attribute("data-attempt-id")
    |> List.first()
  end

  defp playback_error(view, params) do
    render_hook(
      view,
      "playback_error",
      Map.merge(
        %{"attempt_id" => playback_attempt(view), "error_kind" => "media", "position_ms" => "0"},
        params
      )
    )
  end

  defp start_inspected_version(ctx) do
    insert_incompatible_inspection(ctx.second)
    render_click(element(ctx.view, "#movie-play-#{ctx.second.id}"))
    if has_element?(ctx.view, "[data-playback-probe]"), do: negotiate(ctx.view)
    preparing_session(ctx.view)
  end

  defp insert_incompatible_inspection(file), do: inspect!(file, "matroska,webm", "ac3")

  defp preparing_session(view) do
    [_, id] =
      Regex.run(~r/id="movie-video-frame"[^>]*data-session-id="([^"]+)"/, render(view))

    {:ok, session} = TranscodeManager.lookup(id)
    session
  end

  defp make_ready(view, session) do
    File.write!(Path.join(session.directory, "seg-000000.ts"), "segment")

    File.write!(
      Path.join(session.directory, "index.m3u8"),
      "#EXTM3U\n#EXTINF:4.0,\nseg-000000.ts\n#EXT-X-ENDLIST\n"
    )

    send(view.pid, {:transcode_poll, session.id})
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
