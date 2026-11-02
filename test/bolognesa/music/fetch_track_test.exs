defmodule Bolognesa.Music.FetchTrackTest do
  use Bolognesa.DataCase, async: true
  import Bolognesa.MusicFixtures
  alias Bolognesa.Music
  alias Bolognesa.Repo

  test "authorized track read returns a public projection and hides unavailable files" do
    fixture = refresh_fixture(tags: %{"title" => "Authorized song", "artist" => "Example"})
    assert {:ok, track} = Music.fetch_track(fixture.actor, fixture.track.id)
    assert track.id == fixture.track.id
    assert track.file_id == fixture.file.id
    assert track.title == "Authorized song"
    assert track.artist == "Example"
    assert {:error, :forbidden} = Music.fetch_track(nil, fixture.track.id)
    assert {:error, :not_found} = Music.fetch_track(fixture.actor, -1)
    Repo.update!(Ecto.Changeset.change(fixture.file, availability: :missing))
    assert {:error, :not_found} = Music.fetch_track(fixture.actor, fixture.track.id)
    assert {:error, :not_found} = Music.fetch_track(fixture.actor, 999_999)
  end
end
