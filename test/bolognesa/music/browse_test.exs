defmodule Bolognesa.Music.BrowseTest do
  use Bolognesa.DataCase, async: true
  import Bolognesa.MusicFixtures
  alias Bolognesa.Music
  alias Bolognesa.Music.Application.UseCases.AlbumTracks
  alias Bolognesa.Music.StaleCountTracksReader

  test "last listened album is account scoped and distinguishes no activity from failure" do
    f = refresh_fixture(tags: %{"artist" => "Ensemble", "album" => "First"})
    actor = listening_actor()
    other = listening_actor(:member)
    assert {:ok, []} = Music.list_recent_albums(actor, nil)
    record_activity(other.id, f.track.id, ~U[2026-10-06 10:00:00.000000Z])
    assert {:ok, []} = Music.list_recent_albums(actor, nil)
    assert {:error, :forbidden} = Music.list_recent_albums(nil, nil)
    assert {:error, :invalid_query} = Music.list_recent_albums(actor, "1")
    assert {:error, :not_found} = Music.list_recent_albums(actor, 9_999_999)

    record_activity(actor.id, f.track.id, ~U[2026-10-01 10:00:00.123456Z])
    assert {:ok, [album]} = Music.list_recent_albums(actor, nil)
    assert album.id == f.track.album_id
    assert album.title == "First"
    assert album.last_played_at == ~U[2026-10-01 10:00:00.123456Z]
  end

  test "last listened album respects library scope and deterministic ties" do
    actor = listening_actor()
    first = refresh_fixture(tags: %{"album" => "First"})
    second = refresh_fixture(tags: %{"album" => "Second"})
    record_activity(actor.id, first.track.id, ~U[2026-10-01 10:00:00.000000Z])
    record_activity(actor.id, second.track.id, ~U[2026-10-02 10:00:00.000000Z])

    assert {:ok, [latest, _]} = Music.list_recent_albums(actor, nil)
    assert latest.id == second.track.album_id
    assert {:ok, [scoped]} = Music.list_recent_albums(actor, first.library.id)
    assert scoped.id == first.track.album_id

    record_activity(actor.id, first.track.id, ~U[2026-10-02 10:00:00.000000Z])
    assert {:ok, [tied, _]} = Music.list_recent_albums(actor, nil)
    assert tied.id == min(first.track.album_id, second.track.album_id)
  end

  test "last listened considers missing tracks but excludes albums with no available files" do
    actor = listening_actor()
    f = refresh_fixture(tags: %{"album" => "First"})
    {_, [second]} = add_tracks(f, 1)
    record_activity(actor.id, second.id, ~U[2026-10-05 10:00:00.000000Z])
    track = Repo.get!(Bolognesa.Infrastructure.Persistence.MusicTrackSchema, second.id)
    file = Repo.get!(Bolognesa.Infrastructure.Persistence.MediaFileSchema, track.media_file_id)
    Repo.update!(change(file, availability: :missing))
    assert {:ok, [album]} = Music.list_recent_albums(actor, nil)
    assert album.last_played_at == ~U[2026-10-05 10:00:00.000000Z]
    refute album.track_available?
    Repo.update!(change(f.file, availability: :missing))
    assert {:ok, []} = Music.list_recent_albums(actor, nil)
  end

  test "last listened lookup reaches beyond the first album page without per-album queries" do
    actor = listening_actor()
    first = refresh_fixture(tags: %{"album" => "A"})
    record_activity(actor.id, first.track.id, ~U[2026-10-01 10:00:00.000000Z])

    {{:ok, _}, initial_queries} =
      count_queries(fn -> Music.list_recent_albums(actor, nil) end)

    for _ <- 1..50, do: refresh_fixture(tags: %{"album" => "B"})
    last = refresh_fixture(tags: %{"album" => "Z"})
    record_activity(actor.id, last.track.id, ~U[2026-10-06 10:00:00.000000Z])
    {{:ok, [album, _]}, queries} = count_queries(fn -> Music.list_recent_albums(actor, nil) end)
    assert album.id == last.track.album_id
    assert queries == initial_queries
  end

  test "recent albums are limited to three distinct albums in latest activity order" do
    actor = listening_actor()
    fixtures = for i <- 1..5, do: refresh_fixture(tags: %{"album" => "Record #{i}"})

    Enum.with_index(fixtures, 1)
    |> Enum.each(fn {f, day} ->
      record_activity(
        actor.id,
        f.track.id,
        DateTime.add(~U[2026-10-01 00:00:00.000000Z], day, :day)
      )
    end)

    assert {:ok, albums} = Music.list_recent_albums(actor, nil)

    assert Enum.map(albums, & &1.id) ==
             Enum.map(Enum.reverse(fixtures) |> Enum.take(3), & &1.track.album_id)
  end

  test "recent album continuation uses latest heard track and replays when it is last in album order" do
    actor = listening_actor()
    f = refresh_fixture(tags: %{"album" => "First", "disc" => "1", "track" => "1"})
    {_, [second]} = add_tracks(f, 1)
    track = Repo.get!(Bolognesa.Infrastructure.Persistence.MusicTrackSchema, second.id)
    Repo.update!(change(track, disc_number: 2, track_number: 1))
    record_activity(actor.id, f.track.id, ~U[2026-10-01 00:00:00.000000Z])
    assert {:ok, [album]} = Music.list_recent_albums(actor, nil)
    assert album.track_id == f.track.id
    assert album.file_id == f.file.id
    refute album.restart?
    assert album.track_available?
    record_activity(actor.id, second.id, ~U[2026-10-02 00:00:00.000000Z])
    assert {:ok, [album]} = Music.list_recent_albums(actor, nil)
    assert album.track_id == second.id
    assert album.restart?
  end

  test "album activity is the latest track playback for the authenticated account" do
    f = refresh_fixture(tags: %{"artist" => "Ensemble", "album" => "First"})
    actor = listening_actor()
    other = listening_actor(:member)
    {_, [second, _unplayed]} = add_tracks(f, 2)

    record_activity(actor.id, f.track.id, ~U[2026-10-01 10:00:00.000001Z])
    record_activity(actor.id, second.id, ~U[2026-10-02 10:00:00.123456Z])
    record_activity(other.id, f.track.id, ~U[2026-10-03 10:00:00.000000Z])

    assert {:ok, %{items: [album], total: 1}} =
             Music.browse(actor, :albums, nil, "", 1, f.library.id)

    assert album.last_played_at == ~U[2026-10-02 10:00:00.123456Z]

    record_activity(actor.id, f.track.id, ~U[2026-10-04 10:00:00.000000Z])

    assert {:ok, %{items: [updated]}} =
             Music.browse(actor, :albums, nil, "", 1, f.library.id)

    assert updated.last_played_at == ~U[2026-10-04 10:00:00.000000Z]
  end

  test "albums without playback by the account and artist entries have no activity date" do
    f = refresh_fixture(tags: %{"artist" => "Ensemble", "album" => "First"})
    actor = listening_actor()
    other = listening_actor(:member)

    assert {:ok, %{items: [%{last_played_at: nil}]}} =
             Music.browse(actor, :albums, nil, "", 1, nil)

    record_activity(other.id, f.track.id, ~U[2026-10-03 10:00:00.000000Z])

    assert {:ok, %{items: [album]}} = Music.browse(actor, :albums, nil, "", 1, nil)
    assert album.last_played_at == nil
    assert {:error, :forbidden} = Music.browse(other, :albums, nil, "", 1, nil)

    record_activity(actor.id, f.track.id, ~U[2026-10-04 10:00:00.000000Z])
    assert {:ok, %{items: [artist]}} = Music.browse(actor, :artists, nil, "", 1, nil)
    assert artist.last_played_at == nil
  end

  test "album activity includes tracks beyond a page and temporarily missing tracks" do
    f = refresh_fixture(tags: %{"artist" => "Ensemble", "album" => "First"})
    actor = listening_actor()
    {_, tracks} = add_tracks(f, 50)
    last = List.last(tracks)
    record_activity(actor.id, last.id, ~U[2026-10-05 10:00:00.000000Z])

    track = Repo.get!(Bolognesa.Infrastructure.Persistence.MusicTrackSchema, last.id)
    file = Repo.get!(Bolognesa.Infrastructure.Persistence.MediaFileSchema, track.media_file_id)
    Repo.update!(change(file, availability: :missing))

    assert {:ok, %{items: [album]}} =
             Music.browse(actor, :albums, f.track.artist_id, "First", 1, f.library.id)

    assert album.last_played_at == ~U[2026-10-05 10:00:00.000000Z]
  end

  test "album activity stays within its album and library when browsing all libraries" do
    f = refresh_fixture(tags: %{"artist" => "Ensemble", "album" => "First"})
    actor = listening_actor()
    record_activity(actor.id, f.track.id, ~U[2026-10-01 10:00:00.000000Z])

    {{:ok, %{items: [_], total: 1}}, initial_queries} =
      count_queries(fn -> Music.browse(actor, :albums, nil, "", 1, nil) end)

    other = refresh_fixture(tags: %{"artist" => "Ensemble", "album" => "First"})
    record_activity(actor.id, other.track.id, ~U[2026-10-06 10:00:00.000000Z])

    {{:ok, %{items: albums, total: 2}}, queries} =
      count_queries(fn -> Music.browse(actor, :albums, nil, "", 1, nil) end)

    assert queries == initial_queries
    dates = Map.new(albums, &{&1.id, &1.last_played_at})
    assert dates[f.track.album_id] == ~U[2026-10-01 10:00:00.000000Z]
    assert dates[other.track.album_id] == ~U[2026-10-06 10:00:00.000000Z]

    assert {:ok, %{items: [album], total: 1}} =
             Music.browse(actor, :albums, nil, "", 1, f.library.id)

    assert album.id == f.track.album_id
    assert album.last_played_at == ~U[2026-10-01 10:00:00.000000Z]
  end

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

  test "artist browsing prefers the album credit and hides unavailable files" do
    f =
      refresh_fixture(
        tags: %{"artist" => "Solo", "album_artist" => "Ensemble", "album" => "First"}
      )

    assert {:ok, %{items: artists, total: 1}} =
             Music.browse(f.actor, :artists, nil, "", 1, f.library.id)

    assert Enum.map(artists, & &1.title) == ["Ensemble"]

    assert {:ok, %{items: [album]}} =
             Music.browse(f.actor, :albums, hd(artists).id, "", 1, f.library.id)

    assert album.id == f.track.album_id

    assert {:ok, %{items: [track]}} =
             Music.list_album_tracks(f.actor, album.id, "", 1, f.library.id)

    assert track.artist == "Solo"

    Repo.update!(change(f.file, availability: :missing))

    assert {:ok, %{items: [], total: 0}} =
             Music.browse(f.actor, :artists, nil, "", 1, f.library.id)
  end

  test "tracks without an album remain browsable by their artist" do
    f = refresh_fixture(tags: %{"artist" => "Solo"})

    assert {:ok, %{items: [artist], total: 1}} =
             Music.browse(f.actor, :artists, nil, "", 1, f.library.id)

    assert artist.title == "Solo"
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
    actor = %Bolognesa.Accounts.Domain.Entities.AuthenticatedUser{id: 1, role: :admin}

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

    Repo.insert_all(Bolognesa.Infrastructure.Persistence.MusicTrackSchema, tracks,
      returning: [:id],
      log: false
    )
  end

  defp listening_actor(role \\ :admin) do
    user =
      Repo.insert!(%Bolognesa.Infrastructure.Persistence.UserSchema{
        name: "Listener",
        email: "listener-#{System.unique_integer([:positive])}@example.com",
        role: Atom.to_string(role),
        hashed_password: "unused"
      })

    %Bolognesa.Accounts.Domain.Entities.AuthenticatedUser{id: user.id, role: role}
  end

  defp record_activity(user_id, track_id, played_at) do
    Repo.query!(
      """
      INSERT INTO music_listening_activity (user_id, track_id, last_played_at)
      VALUES ($1, $2, $3)
      ON CONFLICT (user_id, track_id) DO UPDATE SET last_played_at = EXCLUDED.last_played_at
      """,
      [user_id, track_id, played_at]
    )
  end

  defp count_queries(fun) do
    reference = make_ref()

    :ok =
      :telemetry.attach(
        reference,
        [:bolognesa, :repo, :query],
        fn _event, _measurements, _metadata, {owner, tag} ->
          if self() == owner, do: send(owner, {tag, :query})
        end,
        {self(), reference}
      )

    try do
      result = fun.()
      {result, query_count(reference, 0)}
    after
      :telemetry.detach(reference)
    end
  end

  defp query_count(reference, count) do
    receive do
      {^reference, :query} -> query_count(reference, count + 1)
    after
      0 -> count
    end
  end
end
