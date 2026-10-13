defmodule Bolognesa.Music.ListTracksTest do
  use Bolognesa.DataCase, async: true
  import Bolognesa.MusicFixtures
  alias Bolognesa.Music

  test "authorized library-scoped reads include processing and failures without a track" do
    ready = refresh_fixture(tags: %{"title" => "Sample", "artist" => "Ensemble"})
    pending = music_fixture(inspection_state: :pending)
    failed = music_fixture(inspection_state: :failed)
    assert {:error, :forbidden} = Music.list_tracks(nil, "", 1, nil)
    assert {:ok, page} = Music.list_tracks(ready.actor, "", 1, nil)
    assert page.total == 3
    assert Enum.find(page.items, &(&1.file_id == ready.file.id)).state == :ready
    assert Enum.find(page.items, &(&1.file_id == pending.file.id)).state == :pending
    assert Enum.find(page.items, &(&1.file_id == failed.file.id)).state == :inspection_failed

    assert {:ok, %{items: [track], total: 1}} =
             Music.list_tracks(ready.actor, "Ensemble", 1, ready.library.id)

    assert track.id == ready.track.id
  end

  test "queries are bounded and percent and underscore are literal" do
    fixture = refresh_fixture(tags: %{"title" => "100%_Song"})
    assert {:ok, %{total: 1}} = Music.list_tracks(fixture.actor, "%_", 1, nil)
    assert {:ok, %{total: 0}} = Music.list_tracks(fixture.actor, "missing%", 1, nil)

    for {query, page} <- [{<<255>>, 1}, {String.duplicate("a", 257), 1}, {"", 0}, {"", 100_001}] do
      assert {:error, :invalid_query} = Music.list_tracks(fixture.actor, query, page, nil)
    end
  end

  test "missing files are excluded and stale observations are processing" do
    fixture = refresh_fixture()
    Repo.update!(change(fixture.file, revision: 2))
    assert {:ok, %{items: [%{state: :pending}]}} = Music.list_tracks(fixture.actor, "", 1, nil)
    Repo.update!(change(fixture.file, availability: :missing))
    assert {:ok, %{total: 0}} = Music.list_tracks(fixture.actor, "", 1, nil)
  end
end
