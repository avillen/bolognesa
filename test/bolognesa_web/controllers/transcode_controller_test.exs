defmodule BolognesaWeb.TranscodeControllerTest do
  use BolognesaWeb.ConnCase, async: false

  alias Bolognesa.Accounts
  alias Bolognesa.Infrastructure.LocalSourcePath
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.MovieSchema
  alias Bolognesa.Playback
  alias Bolognesa.Playback.Infrastructure.TranscodeManager
  alias Bolognesa.Repo

  test "a manifest requires an authenticated session", %{conn: conn} do
    conn = get(conn, "/movies/1/media/2/hls/00000000-0000-0000-0000-000000000000/index.m3u8")
    assert conn.status == 401
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
  end

  test "an arbitrary segment name is rejected without bytes", %{conn: conn} do
    {:ok, _} =
      Accounts.install_admin(%{
        name: "Ada",
        email: "hls@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} = Accounts.start_session("hls@example.com", "correct horse battery staple")

    conn =
      get(
        init_test_session(conn, user_token: token),
        "/movies/1/media/2/hls/00000000-0000-0000-0000-000000000000/secret.txt"
      )

    assert conn.status == 404
    assert conn.resp_body == ""
  end

  test "serves private HLS and rejects a revoked association", %{conn: conn} do
    {:ok, actor} =
      Accounts.install_admin(%{
        name: "Ada",
        email: "hls-real@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} = Accounts.start_session("hls-real@example.com", "correct horse battery staple")
    base = hd(Application.fetch_env!(:bolognesa, :library_roots))
    directory = Path.join(base, "hls-http-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    {:ok, physical} = LocalSourcePath.canonical_directory(directory)
    original = Path.join(physical, "film.avi")
    File.write!(original, "abcdefgh")
    {:ok, stat} = File.stat(original, time: :posix)

    movie =
      Repo.insert!(movie_changeset(%{provider: :tmdb, provider_id: 991, title: "Fixture"}))

    library =
      Repo.insert!(
        LibrarySchema.changeset(
          %LibrarySchema{},
          %{name: "HLS", path: physical}
        )
      )

    file =
      Repo.insert!(
        MediaFileSchema.changeset(%MediaFileSchema{}, %{
          library_id: library.id,
          relative_path: "film.avi",
          size_bytes: 8,
          modified_at: DateTime.from_unix!(stat.mtime * 1_000_000, :microsecond),
          last_seen_generation: Ecto.UUID.generate()
        })
      )

    identification =
      Bolognesa.MovieIdentificationFixtures.insert_decision!(
        %{
          media_file_id: file.id,
          observed_revision: file.revision,
          token: Ecto.UUID.generate(),
          state: :manual,
          origin: :manual
        },
        movie.id
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

      File.rm_rf!(directory)
    end)

    assert {:ok, session} =
             Playback.start_compatible(actor, {:movie, movie.id}, file.id, 0, :video)

    for {request_actor, entry_id, file_id} <- [
          {%{actor | id: actor.id + 1}, movie.id, file.id},
          {actor, movie.id + 1, file.id},
          {actor, movie.id, file.id + 1}
        ] do
      assert {:error, :not_found} =
               Playback.compatible_session(request_actor, {:movie, entry_id}, file_id, session.id)

      assert {:ok, ^session} = TranscodeManager.lookup(session.id)
    end

    File.write!(Path.join(session.directory, "seg-000000.ts"), "synthetic segment")

    File.write!(
      Path.join(session.directory, "index.m3u8"),
      "#EXTM3U\n#EXTINF:4.0,\nseg-000000.ts\n"
    )

    path = "/movies/#{movie.id}/media/#{file.id}/hls/#{session.id}"

    manifest = get(init_test_session(conn, user_token: token), path <> "/index.m3u8")
    assert response(manifest, 200) =~ "seg-000000.ts"
    assert get_resp_header(manifest, "cache-control") == ["private, no-store"]
    segment = get(init_test_session(conn, user_token: token), path <> "/seg-000000.ts")
    assert response(segment, 200) == "synthetic segment"

    Repo.update!(MediaFileSchema.changeset(file, %{revision: file.revision + 1}))

    assert {:error, :source_changed} =
             Playback.compatible_session(actor, {:movie, movie.id}, file.id, session.id)

    assert {:error, :not_found} = TranscodeManager.lookup(session.id)
    Repo.update!(MediaFileSchema.changeset(file, %{revision: file.revision}))

    assert {:ok, next_session} =
             Playback.start_compatible(actor, {:movie, movie.id}, file.id, 0, :video)

    File.write!(Path.join(next_session.directory, "seg-000000.ts"), "synthetic segment")
    path = "/movies/#{movie.id}/media/#{file.id}/hls/#{next_session.id}"

    Repo.delete!(identification)
    denied = get(init_test_session(conn, user_token: token), path <> "/seg-000000.ts")
    assert response(denied, 404) == ""
    assert {:error, :not_found} = TranscodeManager.lookup(next_session.id)
  end

  defp movie_changeset(attrs),
    do: MovieSchema.changeset(%MovieSchema{}, Map.put_new(attrs, :provider, :tmdb))
end
