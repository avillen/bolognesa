defmodule Bolognesa.Music.RescanActivityTest do
  alias Bolognesa.MusicFixtures
  use Bolognesa.DataCase, async: true

  import Bolognesa.MusicFixtures

  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser

  alias Bolognesa.Infrastructure.Persistence.InspectionSchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.MusicTrackSchema
  alias Bolognesa.Infrastructure.Persistence.UserSchema

  alias Bolognesa.Libraries.Domain.ValueObjects.Files.NewMediaFile
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoScanRepository
  alias Bolognesa.Music

  test "rescans and metadata refresh retain each account's activity at the same path" do
    f = refresh_fixture(tags: %{"album" => "Original", "title" => "First"})
    first = actor()
    second = actor(:member)
    first_date = ~U[2026-10-01 10:00:00.123456Z]
    second_date = ~U[2026-10-02 10:00:00.000000Z]
    record(first, f.track, first_date)
    record(second, f.track, second_date)

    scan(f.library.id, [entry(f.file.relative_path, 10)])
    assert_date(first, f, first_date)
    assert_stored_date(second, f.track, second_date)

    # A replacement at the same path is the same inventory identity.
    scan(f.library.id, [entry(f.file.relative_path, 20)])
    inspection = Repo.get_by!(InspectionSchema, media_file_id: f.file.id)

    Repo.update!(
      change(inspection,
        state: :succeeded,
        music_tags: %{"album" => "New", "title" => "Second"},
        tracks: %{"items" => [%{"kind" => "audio", "codec" => "mp3"}]}
      )
    )

    assert :ok = Music.refresh_track(f.file.id, 2)
    updated = Repo.get_by!(MusicTrackSchema, media_file_id: f.file.id)
    assert updated.id == f.track.id
    assert updated.title == "Second"
    assert_date(first, f, first_date)
    assert_stored_date(second, f.track, second_date)
    assert {:ok, [album]} = Music.list_recent_albums(first, f.library.id)
    assert album.title == "New"
    assert album.last_played_at == first_date
  end

  test "missing and renamed paths retain activity only with the original identity" do
    f = refresh_fixture(tags: %{"album" => "Original"})
    listener = actor()
    date = ~U[2026-10-01 10:00:00.123456Z]
    record(listener, f.track, date)

    scan(f.library.id, [entry("album/renamed.mp3", 10)])
    assert Repo.get!(MediaFileSchema, f.file.id).availability == :missing
    assert {:ok, %{items: [_]}} = Music.list_tracks(listener, "", 1, f.library.id)

    renamed =
      Repo.get_by!(MediaFileSchema, library_id: f.library.id, relative_path: "album/renamed.mp3")

    refute renamed.id == f.file.id
    inspection = Repo.get_by!(InspectionSchema, media_file_id: renamed.id)

    Repo.update!(
      change(inspection,
        state: :succeeded,
        format: "mp3",
        tracks: %{"items" => [%{"kind" => "audio", "codec" => "mp3"}]},
        music_tags: %{"album" => "Original"}
      )
    )

    assert :ok = Music.refresh_track(renamed.id, renamed.revision)
    assert {:ok, %{items: [track]}} = Music.list_tracks(listener, "", 1, f.library.id)
    assert track.file_id == renamed.id
    assert track.last_played_at == nil

    scan(f.library.id, [entry(f.file.relative_path, 10)])
    assert_date(listener, f, date)
  end

  defp actor(role \\ :admin) do
    user =
      Repo.insert!(%UserSchema{
        name: "Listener",
        email: "listener-#{System.unique_integer([:positive])}@example.com",
        role: Atom.to_string(role),
        hashed_password: "unused"
      })

    %AuthenticatedUser{id: user.id, role: role}
  end

  defp record(actor, track, date) do
    Repo.query!(
      "INSERT INTO music_listening_activity (user_id, track_id, last_played_at) VALUES ($1, $2, $3)",
      [actor.id, track.id, date]
    )
  end

  defp assert_date(actor, fixture, date) do
    assert {:ok, %{items: [track]}} = Music.list_tracks(actor, "", 1, fixture.library.id)
    assert track.id == fixture.track.id
    assert track.last_played_at == date
  end

  defp assert_stored_date(actor, track, date) do
    expected = DateTime.to_naive(date)

    assert %{rows: [[^expected]]} =
             Repo.query!(
               "SELECT last_played_at FROM music_listening_activity WHERE user_id = $1 AND track_id = $2",
               [actor.id, track.id]
             )
  end

  defp entry(path, size) do
    {:ok, entry} =
      NewMediaFile.new(%{
        relative_path: path,
        size_bytes: size,
        modified_at: ~U[2026-10-03 00:00:00Z]
      })

    entry
  end

  defp scan(library_id, entries) do
    assert {:ok, scan} = EctoScanRepository.request(library_id)
    assert {:ok, running, _} = EctoScanRepository.begin_attempt(scan.id, 1)
    assert {:ok, _} = EctoScanRepository.save_batch(scan.id, running.generation, entries)
    assert {:ok, _} = EctoScanRepository.complete(scan.id, running.generation)
  end
end
