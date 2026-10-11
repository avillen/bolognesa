defmodule BolognesaWeb.Movie.Show.LiveTest do
  use BolognesaWeb.ConnCase, async: false
  alias Bolognesa.Infrastructure.Persistence.CatalogEntrySchema
  import Phoenix.LiveViewTest

  alias Bolognesa.Identity
  alias Bolognesa.Infrastructure.LocalSourcePath
  alias Bolognesa.Infrastructure.Persistence.InspectionSchema
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.MovieSchema
  alias Bolognesa.Playback.Infrastructure.TranscodeManager
  alias Bolognesa.Repo

  test "shows movie details and versions container", %{conn: conn} do
    {:ok, _} =
      Identity.install_admin(%{
        name: "Ada",
        email: "show@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} = Identity.start_session("show@example.com", "correct horse battery staple")

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
  end

  test "each confirmed version can open manual correction", %{conn: conn} do
    {:ok, _} =
      Identity.install_admin(%{
        name: "Ada",
        email: "correct-show@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} =
      Identity.start_session("correct-show@example.com", "correct horse battery staple")

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

    Bolognesa.IdentificationFixtures.insert_decision!(
      %{
        media_file_id: file.id,
        observed_revision: 1,
        token: Ecto.UUID.generate(),
        state: :automatic,
        origin: :automatic
      },
      [movie.id]
    )

    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/movies/#{movie.id}")
    render_async(view)

    assert has_element?(
             view,
             "#movie-correct-#{file.id}[href='/movies/review?file_id=#{file.id}']"
           )
  end

  test "selects available versions and clears an old playback error", %{conn: conn} do
    {:ok, _} =
      Identity.install_admin(%{
        name: "Ada",
        email: "play-show@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} =
      Identity.start_session("play-show@example.com", "correct horse battery staple")

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

    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/movies/#{movie.id}")
    render_async(view)

    assert has_element?(view, "#movie-play-#{first.id}")
    assert has_element?(view, "#movie-play-#{second.id}")
    refute has_element?(view, "#movie-play-#{missing.id}")

    render_click(element(view, "#movie-play-#{first.id}"))
    assert has_element?(view, "#movie-player video[src='/movies/#{movie.id}/media/#{first.id}']")
    render_hook(view, "playback_error", %{"file_id" => Integer.to_string(first.id)})
    assert has_element?(view, "#movie-playback-error[role='alert']")
    assert has_element?(view, "#movie-compatible-#{first.id}", "Probar modo compatible")

    render_click(element(view, "#movie-play-#{second.id}"))
    assert has_element?(view, "#movie-player video[src='/movies/#{movie.id}/media/#{second.id}']")
    refute has_element?(view, "#movie-video-#{first.id}")
    refute has_element?(view, "#movie-playback-error")
    render_hook(view, "playback_error", %{"file_id" => Integer.to_string(first.id)})
    refute has_element?(view, "#movie-playback-error")

    Repo.insert!(
      InspectionSchema.changeset(%InspectionSchema{}, %{
        media_file_id: second.id,
        token: Ecto.UUID.generate(),
        observed_revision: second.revision,
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

    render_click(element(view, "#movie-play-#{second.id}"))
    assert has_element?(view, "#movie-playback-preparing", "Preparando reproducción")
    refute has_element?(view, "#movie-player video[src]")

    html = render(view)

    [_, session_id] =
      Regex.run(~r/id="movie-playback-preparing"[^>]*data-session-id="([^"]+)"/, html)

    {:ok, session} = TranscodeManager.lookup(session_id)
    File.write!(Path.join(session.directory, "seg-000000.ts"), "segment")

    File.write!(
      Path.join(session.directory, "index.m3u8"),
      "#EXTM3U\n#EXTINF:4.0,\nseg-000000.ts\n"
    )

    send(view.pid, {:compatible_poll, session_id})
    assert has_element?(view, "#movie-video-#{session_id}[data-src$='/index.m3u8']")
    assert has_element?(view, "#movie-seek-#{session_id}")

    render_hook(view, "playback_pause", %{"session_id" => session_id})
    assert {:ok, _} = TranscodeManager.lookup(session_id)
    assert has_element?(view, "#movie-video-#{session_id}[data-paused-server='true']")
    render_hook(view, "playback_resume", %{"session_id" => session_id, "position_ms" => "1000"})
    assert has_element?(view, "#movie-video-#{session_id}[data-paused-server='false']")
    render_hook(view, "playback_seek", %{"session_id" => session_id, "position_ms" => 1000})
    assert has_element?(view, "#movie-video-#{session_id}")

    render_hook(view, "playback_seek", %{"session_id" => session_id, "position_ms" => "10000"})
    assert has_element?(view, "#movie-playback-preparing")
    assert {:error, :not_found} = TranscodeManager.lookup(session_id)

    render_click(element(view, "#movie-play-#{first.id}"))
    render_hook(view, "playback_error", %{"file_id" => Integer.to_string(first.id)})
    render_click(element(view, "#movie-compatible-#{first.id}"))

    [_, forced_id] =
      Regex.run(
        ~r/id="movie-playback-preparing"[^>]*data-session-id="([^"]+)"/,
        render(view)
      )

    {:ok, forced_session} = TranscodeManager.lookup(forced_id)
    assert forced_session.profile == :video
    render_hook(view, "playback_seek", %{"session_id" => forced_id, "position_ms" => "1000"})
    assert has_element?(view, "#movie-playback-preparing")
    refute has_element?(view, "#movie-playback-error")

    File.rm!(Path.join(physical, "first.mp4"))
    render_click(element(view, "#movie-play-#{first.id}"))
    assert has_element?(view, "#movie-playback-error[data-reason='file_unavailable']")
  end

  test "shows the first selection error when the file has disappeared", %{conn: conn} do
    {:ok, _} =
      Identity.install_admin(%{
        name: "Ada",
        email: "missing-play@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} =
      Identity.start_session("missing-play@example.com", "correct horse battery staple")

    movie =
      Repo.insert!(
        movie_changeset(%{
          provider: :tmdb,
          provider_id: 1002,
          title: "Mi pelicula"
        })
      )

    base = hd(Application.fetch_env!(:bolognesa, :library_roots))
    directory = Path.join(base, "missing-play-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    {:ok, physical} = LocalSourcePath.canonical_directory(directory)
    physical_file = Path.join(physical, "film.mp4")
    File.write!(physical_file, "abcdefgh")

    library =
      Repo.insert!(LibrarySchema.changeset(%LibrarySchema{}, %{name: "Play", path: physical}))

    file = insert_version(library.id, movie.id, physical, "film.mp4", :available)

    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/movies/#{movie.id}")
    render_async(view)
    File.rm!(physical_file)

    render_click(element(view, "#movie-play-#{file.id}"))
    assert has_element?(view, "#movie-playback-error[data-reason='file_unavailable']")
    refute has_element?(view, "#movie-player video")
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

    Bolognesa.IdentificationFixtures.insert_decision!(
      %{
        media_file_id: file.id,
        observed_revision: 1,
        token: Ecto.UUID.generate(),
        state: :automatic,
        origin: :automatic
      },
      [movie_id]
    )

    file
  end

  defp movie_changeset(attrs) do
    entry =
      Repo.insert!(
        CatalogEntrySchema.changeset(
          %CatalogEntrySchema{},
          %{kind: :movie, provider: :tmdb, resource_type: :movie, provider_id: attrs.provider_id}
        )
      )

    MovieSchema.changeset(%MovieSchema{id: entry.id}, Map.drop(attrs, [:provider, :provider_id]))
  end
end
