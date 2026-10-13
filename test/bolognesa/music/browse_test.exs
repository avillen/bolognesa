defmodule Bolognesa.Music.BrowseTest do
  use Bolognesa.DataCase, async: true
  import Bolognesa.MusicFixtures
  alias Bolognesa.Music
  alias Bolognesa.Music.Application.UseCases.AlbumTracks
  alias Bolognesa.Music.StaleCountTracksReader

  test "artist and album reads are authorized and scoped to their library" do
    f = refresh_fixture(tags: %{"artist" => "Ensemble", "album" => "First"})
    other = refresh_fixture(tags: %{"artist" => "Elsewhere", "album" => "Other"})
    assert {:error, :forbidden} = Music.browse(nil, :artists, nil, "", 1, nil)

    assert {:ok, %{items: [artist], total: 1}} =
             Music.browse(f.actor, :artists, nil, "", 1, f.library.id)

    assert artist.id == f.track.artist_id
    assert artist.title == "Ensemble"

    assert {:ok, %{items: [album]}} =
             Music.browse(f.actor, :albums, artist.id, "", 1, f.library.id)

    assert album.id == f.track.album_id
    assert album.title == "First"

    assert {:error, :not_found} =
             Music.browse(f.actor, :albums, other.track.artist_id, "", 1, f.library.id)

    assert {:error, :not_found} = Music.album_queue(f.actor, other.track.album_id, f.library.id)
    assert {:error, :invalid_query} = Music.browse(f.actor, :artists, nil, "", 0, nil)
  end

  test "album queue follows disc, track, path and ID with missing numbers last" do
    f =
      refresh_fixture(
        tags: %{"artist" => "Ensemble", "album" => "First", "disc" => "1", "track" => "2"}
      )

    second =
      music_fixture(
        relative_path: "album/a.mp3",
        tags: %{"artist" => "Ensemble", "album" => "First", "disc" => "1", "track" => "1"}
      )

    Repo.update!(change(second.file, library_id: f.library.id))
    :ok = Music.refresh_track(second.file.id, 1)

    missing =
      music_fixture(
        relative_path: "album/z.mp3",
        tags: %{"artist" => "Ensemble", "album" => "First"}
      )

    Repo.update!(change(missing.file, library_id: f.library.id))
    :ok = Music.refresh_track(missing.file.id, 1)
    assert {:ok, tracks} = Music.album_queue(f.actor, f.track.album_id, f.library.id)
    assert Enum.map(tracks, & &1.file_id) == [second.file.id, f.file.id, missing.file.id]
    Repo.update!(change(second.file, revision: 2))
    assert {:ok, [first, _, _]} = Music.album_queue(f.actor, f.track.album_id, f.library.id)
    assert first.state == :pending

    assert {:ok, %{items: items}} =
             Music.list_album_tracks(f.actor, f.track.album_id, "", 1, f.library.id)

    assert Enum.map(items, & &1.file_id) == [second.file.id, f.file.id, missing.file.id]
  end

  test "browsing searches literally and hides orphan identities" do
    f = refresh_fixture(tags: %{"artist" => "100%_Ensemble", "album" => "First"})

    assert {:ok, %{items: [_], total: 1}} =
             Music.browse(f.actor, :artists, nil, "%_", 1, f.library.id)

    assert {:ok, %{items: [], total: 0}} =
             Music.browse(f.actor, :artists, nil, "missing%", 1, f.library.id)

    assert {:ok, %{items: [_]}} = Music.browse(f.actor, :albums, nil, "First", 1, f.library.id)
    Repo.update!(change(f.file, availability: :missing))
    assert {:ok, %{total: 0}} = Music.browse(f.actor, :artists, nil, "", 1, f.library.id)
    assert {:ok, %{total: 0}} = Music.browse(f.actor, :albums, nil, "", 1, f.library.id)
  end

  test "album playback spans list pages and refuses oversized queues" do
    f = refresh_fixture(tags: %{"artist" => "Ensemble", "album" => "First"})
    add_tracks(f, 50)

    assert {:ok, %{items: page, total: 51}} =
             Music.list_album_tracks(f.actor, f.track.album_id, "", 1, f.library.id)

    assert length(page) == 50
    assert {:ok, tracks} = Music.album_queue(f.actor, f.track.album_id, f.library.id)
    assert length(tracks) == 51
    add_tracks(f, 450)
    assert {:error, :album_too_large} = Music.album_queue(f.actor, f.track.album_id, f.library.id)
    assert {:error, :forbidden} = Music.album_queue(nil, f.track.album_id, f.library.id)
  end

  test "a count becoming stale during import cannot admit an oversized queue" do
    actor = %Bolognesa.Identity.Domain.Entities.Actor{id: 1, role: :admin}

    assert {:error, :album_too_large} =
             AlbumTracks.queue(
               actor,
               1,
               nil,
               StaleCountTracksReader
             )
  end

  defp add_tracks(f, count) do
    file_attrs = Map.from_struct(f.file) |> Map.drop([:id, :__meta__])
    track_attrs = Map.from_struct(f.track) |> Map.drop([:id, :__meta__])

    files =
      for _ <- 1..count,
          do:
            Map.put(
              file_attrs,
              :relative_path,
              "album/song-#{System.unique_integer([:positive])}.mp3"
            )

    {_, inserted} =
      Repo.insert_all(Bolognesa.Infrastructure.Persistence.MediaFileSchema, files,
        returning: [:id],
        log: false
      )

    tracks = Enum.map(inserted, &Map.put(track_attrs, :media_file_id, &1.id))
    Repo.insert_all(Bolognesa.Infrastructure.Persistence.MusicTrackSchema, tracks, log: false)
  end
end
