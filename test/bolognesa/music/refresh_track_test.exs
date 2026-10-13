defmodule Bolognesa.Music.RefreshTrackTest do
  use Bolognesa.DataCase, async: true
  import Bolognesa.MusicFixtures
  alias Bolognesa.Infrastructure.Persistence.{InspectionSchema, MediaFileSchema, MusicTrackSchema}
  alias Bolognesa.Music
  alias Bolognesa.Music.Domain.ValueObjects.TrackMetadata
  alias Bolognesa.Music.Infrastructure.Readers.EctoObservationsReader
  alias Bolognesa.Music.Infrastructure.Repositories.EctoMusicRepository

  test "duplicate refresh preserves identity and metadata changes update in place" do
    fixture = music_fixture(tags: %{"title" => "First"})
    assert :ok = Music.refresh_track(fixture.file.id, fixture.file.revision)
    first = Repo.get_by!(MusicTrackSchema, media_file_id: fixture.file.id)
    assert :ok = Music.refresh_track(fixture.file.id, fixture.file.revision)
    assert first.id == Repo.get_by!(MusicTrackSchema, media_file_id: fixture.file.id).id

    Repo.update!(
      change(fixture.inspection, token: Ecto.UUID.generate(), music_tags: %{"title" => "Second"})
    )

    assert :ok = Music.refresh_track(fixture.file.id, fixture.file.revision)
    second = Repo.get!(MusicTrackSchema, first.id)
    assert second.title == "Second"
  end

  test "obsolete tokens, revision changes and missing files do not write" do
    for change_kind <- [:token, :revision, :missing] do
      fixture = music_fixture(tags: %{"title" => "Obsolete"})
      {:ok, observation} = EctoObservationsReader.current(fixture.file.id, 1)

      case change_kind do
        :token -> Repo.update!(change(fixture.inspection, token: Ecto.UUID.generate()))
        :revision -> Repo.update!(change(fixture.file, revision: 2))
        :missing -> Repo.update!(change(fixture.file, availability: :missing))
      end

      assert {:ok, :stale} =
               EctoMusicRepository.apply_observation(
                 observation,
                 TrackMetadata.from_observation(observation)
               )

      assert Repo.get_by(MusicTrackSchema, media_file_id: fixture.file.id) == nil
    end
  end

  test "non audio and unsuccessful observations are harmless" do
    fixture = music_fixture(inspection_state: :failed)
    assert :ok = Music.refresh_track(fixture.file.id, 1)

    Repo.update!(
      change(fixture.inspection, state: :succeeded, tracks: %{"items" => [%{"kind" => "video"}]})
    )

    assert :ok = Music.refresh_track(fixture.file.id, 1)
    assert Repo.all(MusicTrackSchema) == []
    assert Repo.get!(MediaFileSchema, fixture.file.id).revision == 1
    assert Repo.get!(InspectionSchema, fixture.inspection.id).state == :succeeded
  end
end
