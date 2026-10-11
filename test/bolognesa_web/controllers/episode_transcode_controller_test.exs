defmodule BolognesaWeb.EpisodeTranscodeControllerTest do
  use BolognesaWeb.ConnCase, async: false
  alias Bolognesa.Identification.Application.CorrectSeriesIdentification

  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository,
    as: Repository

  alias Bolognesa.Infrastructure.Persistence.{
    IdentificationEntrySchema,
    IdentificationSchema,
    MediaFileSchema
  }

  alias Bolognesa.Playback
  alias Bolognesa.Playback.Infrastructure.TranscodeManager
  alias Bolognesa.Repo
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
    assert {:ok, session} = Playback.start_compatible(ctx.actor, first, file.id, 0, :video)

    for {actor, entry, file_id} <- [
          {%{ctx.actor | id: ctx.actor.id + 1}, first, file.id},
          {ctx.actor, second, file.id},
          {ctx.actor, first, file.id + 1}
        ] do
      assert {:error, :not_found} = Playback.compatible_session(actor, entry, file_id, session.id)
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
    assert {:ok, next} = Playback.start_compatible(ctx.actor, second, file.id, 0, :video)
    write_hls(next)
    Repo.update!(MediaFileSchema.changeset(file, %{revision: file.revision + 1}))

    assert {:error, :source_changed} =
             Playback.compatible_session(ctx.actor, second, file.id, next.id)

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

  defp write_hls(session) do
    File.write!(Path.join(session.directory, "seg-000000.ts"), "synthetic segment")

    File.write!(
      Path.join(session.directory, "index.m3u8"),
      "#EXTM3U\n#EXTINF:4.0,\nseg-000000.ts\n"
    )
  end

  test "a container remains unplayable even with a malformed storage association", ctx do
    decision = Repo.get_by!(IdentificationSchema, media_file_id: ctx.media_file.id)

    Repo.insert!(%IdentificationEntrySchema{
      identification_id: decision.id,
      catalog_entry_id: ctx.series_id,
      position: 3
    })

    assert response(get(ctx.conn, "/episodes/#{ctx.series_id}/media/#{ctx.media_file.id}"), 404) ==
             ""

    assert {:error, :not_found} = Playback.prepare(ctx.actor, ctx.series_id, ctx.media_file.id)
  end
end
