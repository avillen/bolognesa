defmodule BolognesaWeb.EpisodeTranscodeControllerTest do
  use BolognesaWeb.ConnCase, async: false
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Playback
  alias Bolognesa.Playback.Infrastructure.TranscodeManager
  alias Bolognesa.Repo
  alias Bolognesa.Series.Application.UseCases.CorrectSeriesIdentification
  alias Bolognesa.Series.Infrastructure.Repositories.EctoIdentificationRepository, as: Repository
  alias Bolognesa.Test.SyntheticSeriesProvider
  alias BolognesaWeb.SeriesFixtures

  setup %{conn: conn} do
    ctx = SeriesFixtures.setup(conn)
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

      File.rm_rf!(ctx.directory)
    end)

    ctx
  end

  test "HLS binds actor episode file and revision then rechecks replacement on every request",
       ctx do
    [first, second] = ctx.episode_ids
    file = ctx.media_file

    assert {:ok, session} =
             Playback.start_compatible(ctx.actor, {:episode, first}, file.id, 0, :video)

    for {actor, entry, file_id} <- [
          {%{ctx.actor | id: ctx.actor.id + 1}, first, file.id},
          {ctx.actor, second, file.id},
          {ctx.actor, first, file.id + 1}
        ] do
      assert {:error, :not_found} =
               Playback.compatible_session(actor, {:episode, entry}, file_id, session.id)
    end

    write_hls(session)
    path = "/episodes/#{first}/media/#{file.id}/hls/#{session.id}"
    assert response(get(ctx.conn, path <> "/index.m3u8"), 200) =~ "seg-000000.ts"
    assert response(get(ctx.conn, path <> "/seg-000000.ts"), 200) == "synthetic segment"
    assert response(get(build_conn(), path <> "/index.m3u8"), 401) == ""

    assert {:ok, _} =
             CorrectSeriesIdentification.call(
               ctx.actor,
               file.id,
               {:tmdb, 201, 0, [2]},
               Repository,
               SyntheticSeriesProvider
             )

    assert response(get(ctx.conn, path <> "/index.m3u8"), 404) == ""
    assert response(get(ctx.conn, path <> "/seg-000000.ts"), 404) == ""
    assert response(get(ctx.conn, "/episodes/#{first}/media/#{file.id}"), 404) == ""
    assert response(get(ctx.conn, "/episodes/#{second}/media/#{file.id}"), 200) == "abcdefgh"

    assert {:ok, next} =
             Playback.start_compatible(ctx.actor, {:episode, second}, file.id, 0, :video)

    write_hls(next)
    Repo.update!(MediaFileSchema.changeset(file, %{revision: file.revision + 1}))

    assert {:error, :source_changed} =
             Playback.compatible_session(ctx.actor, {:episode, second}, file.id, next.id)

    assert {:error, :not_found} = TranscodeManager.lookup(next.id)

    assert response(
             get(ctx.conn, "/episodes/#{second}/media/#{file.id}/hls/#{next.id}/seg-000000.ts"),
             404
           ) == ""
  end

  test "a missing episode file cannot be served", ctx do
    Repo.update!(MediaFileSchema.changeset(ctx.media_file, %{availability: :missing}))

    assert response(get(ctx.conn, "/episodes/#{ctx.episode_id}/media/#{ctx.media_file.id}"), 404) ==
             ""
  end

  test "equal movie and episode IDs cannot cross direct or HLS routes", ctx do
    id = ctx.episode_id

    movie =
      Repo.insert!(%Bolognesa.Infrastructure.Persistence.MovieSchema{
        id: id,
        provider: :tmdb,
        provider_id: 850_001,
        title: "Synthetic movie"
      })

    directory = Path.join(ctx.library.path, "movie-source")
    File.mkdir_p!(directory)
    path = Path.join(directory, "Movie.avi")
    File.write!(path, "movie bytes")
    {:ok, stat} = File.stat(path, time: :posix)

    library =
      Repo.insert!(%Bolognesa.Infrastructure.Persistence.LibrarySchema{
        name: "Movies",
        path: directory,
        content_type: :movie
      })

    file =
      Repo.insert!(%MediaFileSchema{
        library_id: library.id,
        relative_path: "Movie.avi",
        size_bytes: stat.size,
        modified_at: DateTime.from_unix!(stat.mtime * 1_000_000, :microsecond),
        revision: 1,
        availability: :available,
        last_seen_generation: Ecto.UUID.generate()
      })

    Bolognesa.MovieIdentificationFixtures.insert_decision!(
      %{
        media_file_id: file.id,
        observed_revision: 1,
        token: Ecto.UUID.generate(),
        state: :manual,
        origin: :manual
      },
      movie.id
    )

    assert {:ok, %{relative_path: "Movie.avi"}} = Playback.start(ctx.actor, {:movie, id}, file.id)

    assert {:ok, %{relative_path: "Serie S00E01E02.mp4"}} =
             Playback.start(ctx.actor, {:episode, id}, ctx.media_file.id)

    assert {:error, :not_found} = Playback.start(ctx.actor, {:episode, id}, file.id)
    assert {:error, :not_found} = Playback.start(ctx.actor, {:movie, id}, ctx.media_file.id)
    assert response(get(ctx.conn, "/movies/#{id}/media/#{file.id}"), 200) == "movie bytes"

    assert response(get(ctx.conn, "/episodes/#{id}/media/#{ctx.media_file.id}"), 200) ==
             "abcdefgh"

    assert response(get(ctx.conn, "/movies/#{id}/media/#{ctx.media_file.id}"), 404) == ""
    assert response(get(ctx.conn, "/episodes/#{id}/media/#{file.id}"), 404) == ""

    for {kind, source_file, other_kind} <- [
          {:movie, file, :episode},
          {:episode, ctx.media_file, :movie}
        ] do
      assert {:ok, session} =
               Playback.start_compatible(ctx.actor, {kind, id}, source_file.id, 0, :video)

      assert session.content_ref == {kind, id}
      write_hls(session)
      route = if kind == :movie, do: "movies", else: "episodes"
      other_route = if other_kind == :movie, do: "movies", else: "episodes"
      base = "/#{route}/#{id}/media/#{source_file.id}/hls/#{session.id}"
      wrong = "/#{other_route}/#{id}/media/#{source_file.id}/hls/#{session.id}"
      assert response(get(ctx.conn, base <> "/index.m3u8"), 200) =~ "#EXTM3U"
      assert response(get(ctx.conn, base <> "/seg-000000.ts"), 200) == "synthetic segment"
      assert response(get(ctx.conn, wrong <> "/index.m3u8"), 404) == ""
      assert response(get(ctx.conn, wrong <> "/seg-000000.ts"), 404) == ""
      query = "?#{kind}_id=#{id}"

      injected_statuses =
        Enum.map(["/index.m3u8", "/seg-000000.ts"], fn suffix ->
          get(ctx.conn, wrong <> suffix <> query).status
        end)

      assert injected_statuses == [404, 404]

      assert {:ok, _} =
               Playback.compatible_session(ctx.actor, {kind, id}, source_file.id, session.id)

      Playback.stop_compatible(ctx.actor, session.id)
    end
  end

  defp write_hls(session) do
    File.write!(Path.join(session.directory, "seg-000000.ts"), "synthetic segment")

    File.write!(
      Path.join(session.directory, "index.m3u8"),
      "#EXTM3U\n#EXTINF:4.0,\nseg-000000.ts\n"
    )
  end

  test "container references remain unplayable when their numeric IDs overlap episodes", ctx do
    for kind <- [:series, :season] do
      assert {:error, :not_found} =
               Playback.prepare(ctx.actor, {kind, ctx.episode_id}, ctx.media_file.id)
    end
  end
end
