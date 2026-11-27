defmodule Bolognesa.Music.ListTracksTest do
  alias Bolognesa.MusicFixtures
  use Bolognesa.DataCase, async: true
  import Bolognesa.MusicFixtures
  alias Bolognesa.Music

  test "authorized library-scoped reads include processing and failures without a track" do
    ready = refresh_fixture(tags: %{"title" => "Sample", "artist" => "Ensemble"})
    pending = music_fixture(inspection_state: :pending)
    failed = music_fixture(inspection_state: :failed)
    assert {:error, :forbidden} = Music.list_tracks(nil, "", 1, nil)
    assert {:ok, page} = Music.list_tracks(ready.actor, "", 1, nil)
    assert length(page.items) == 3
    assert page.total == nil
    assert Enum.find(page.items, &(&1.file_id == ready.file.id)).state == :ready
    assert Enum.find(page.items, &(&1.file_id == pending.file.id)).state == :pending
    assert Enum.find(page.items, &(&1.file_id == failed.file.id)).state == :inspection_failed

    assert {:ok, %{items: [track]}} =
             Music.list_tracks(ready.actor, "Ensemble", 1, ready.library.id)

    assert track.id == ready.track.id
  end

  test "queries are bounded and percent and underscore are literal" do
    fixture = refresh_fixture(tags: %{"title" => "100%_Song"})
    assert {:ok, %{items: [_]}} = Music.list_tracks(fixture.actor, "%_", 1, nil)
    assert {:ok, %{items: []}} = Music.list_tracks(fixture.actor, "missing%", 1, nil)

    for {query, page} <- [{<<255>>, 1}, {String.duplicate("a", 257), 1}] do
      assert {:error, :invalid_query} = Music.list_tracks(fixture.actor, query, page, nil)
    end

    for page <- [0, 100_001] do
      assert {:error, :invalid_page} = Music.list_tracks(fixture.actor, "", page, nil)
    end
  end

  test "pending tracks sort by displayed filename" do
    first = music_fixture(relative_path: "z/Alpha.mp3", inspection_state: :pending)
    second = music_fixture(relative_path: "a/Zeta.mp3", inspection_state: :pending)
    assert {:ok, %{items: [alpha, zeta]}} = Music.list_tracks(first.actor, "", 1, nil)
    assert alpha.file_id == first.file.id
    assert zeta.file_id == second.file.id
  end

  test "pagination is bounded and non-music libraries are rejected" do
    fixture = music_fixture()

    attrs =
      Map.take(Map.from_struct(fixture.file), [
        :library_id,
        :size_bytes,
        :modified_at,
        :availability,
        :revision,
        :last_seen_generation
      ])

    rows = for number <- 1..50, do: Map.put(attrs, :relative_path, "song-#{number}.mp3")
    Repo.insert_all(Bolognesa.Infrastructure.Persistence.MediaFileSchema, rows, log: false)

    assert {:ok, %{items: first, has_next?: true, page_size: 50}} =
             Music.list_tracks(fixture.actor, "", 1, fixture.library.id)

    assert length(first) == 50

    assert {:ok, %{items: [_last], has_next?: false}} =
             Music.list_tracks(fixture.actor, "", 2, fixture.library.id)

    assert {:ok, %{items: [], has_next?: false}} =
             Music.list_tracks(fixture.actor, "", 3, fixture.library.id)

    Repo.update!(change(fixture.library, content_type: :movie))
    assert {:error, :not_found} = Music.list_tracks(fixture.actor, "", 1, fixture.library.id)
  end

  test "missing files are excluded and stale observations are processing" do
    fixture = refresh_fixture()
    Repo.update!(change(fixture.file, revision: 2))
    assert {:ok, %{items: [%{state: :pending}]}} = Music.list_tracks(fixture.actor, "", 1, nil)
    Repo.update!(change(fixture.file, availability: :missing))
    assert {:ok, %{items: []}} = Music.list_tracks(fixture.actor, "", 1, nil)
  end
end
