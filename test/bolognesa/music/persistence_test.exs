defmodule Bolognesa.Music.PersistenceTest do
  use Bolognesa.DataCase, async: true
  import Bolognesa.MusicFixtures

  alias Bolognesa.Infrastructure.Persistence.{
    MusicAlbumSchema,
    MusicArtistSchema,
    MusicTrackSchema
  }

  test "unique file association and bounded numbers" do
    fixture = music_fixture()

    attrs = %{
      media_file_id: fixture.file.id,
      library_id: fixture.library.id,
      title: "Sample",
      observed_revision: 1,
      inspection_token: fixture.inspection.token
    }

    assert {:ok, _track} = Repo.insert(MusicTrackSchema.changeset(%MusicTrackSchema{}, attrs))

    assert {:error, changeset} =
             Repo.insert(MusicTrackSchema.changeset(%MusicTrackSchema{}, attrs))

    assert errors_on(changeset).media_file_id != []

    assert {:error, changeset} =
             Repo.insert(
               MusicTrackSchema.changeset(
                 %MusicTrackSchema{},
                 Map.merge(attrs, %{media_file_id: music_fixture().file.id, track_number: 10000})
               )
             )

    assert errors_on(changeset).track_number != []
  end

  test "artists and albums without an artist have unique local keys" do
    fixture = music_fixture()
    artist = %{library_id: fixture.library.id, name: "Sample", normalized_name: "sample"}
    assert {:ok, _} = Repo.insert(MusicArtistSchema.changeset(%MusicArtistSchema{}, artist))
    assert {:error, _} = Repo.insert(MusicArtistSchema.changeset(%MusicArtistSchema{}, artist))

    album = %{
      library_id: fixture.library.id,
      source_parent: "album",
      title: "Album",
      normalized_title: "album",
      album_artist_key: ""
    }

    assert {:ok, _} = Repo.insert(MusicAlbumSchema.changeset(%MusicAlbumSchema{}, album))
    assert {:error, _} = Repo.insert(MusicAlbumSchema.changeset(%MusicAlbumSchema{}, album))
  end

  test "inventory cannot be deleted beneath a track" do
    fixture = music_fixture()

    Repo.insert!(
      MusicTrackSchema.changeset(%MusicTrackSchema{}, %{
        media_file_id: fixture.file.id,
        library_id: fixture.library.id,
        title: "Sample",
        observed_revision: 1,
        inspection_token: fixture.inspection.token
      })
    )

    assert_raise Ecto.ConstraintError, fn -> Repo.delete!(fixture.file) end
  end
end
