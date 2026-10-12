defmodule Bolognesa.Catalog.SeriesQueriesTest do
  use Bolognesa.DataCase, async: false
  alias Bolognesa.Catalog
  alias Bolognesa.Identity.Domain.Entities.Actor
  alias Bolognesa.Infrastructure.Persistence.{CatalogEntrySchema, InspectionSchema, MovieSchema}
  alias Bolognesa.SeriesFixtures
  @actor %Actor{id: 1, role: :admin}

  test "groups versions and multi episode files without inflating catalog counts" do
    library = SeriesFixtures.library()
    double = SeriesFixtures.file(library.id, "Serie S00E01E02.mkv")
    decision = SeriesFixtures.identify(double, 0, [1, 2])
    single = SeriesFixtures.file(library.id, "Serie S00E01.mp4")
    SeriesFixtures.identify(single, 0, [1])
    assert {:ok, page} = Catalog.search_series(@actor, "Serie", 1)
    assert page.total == 1
    assert [item] = page.items
    assert item.episode_count == 2
    assert {:ok, detail} = Catalog.get_series(@actor, item.id)
    assert [%{number: 0, episode_count: 2} = season] = detail.seasons
    assert {:ok, episodes} = Catalog.list_episodes(@actor, season.id, 1)
    assert Enum.map(episodes.items, & &1.number) == [1, 2]
    assert hd(episodes.items).version_count == 2
    assert {:ok, episode} = Catalog.get_episode(@actor, hd(decision.catalog_entry_ids))
    assert episode.series.title == "Serie"
    assert length(episode.versions) == 2
    assert Enum.map(episode.versions, & &1.episode_numbers) == [[1, 2], [1]]
    single |> Ecto.Changeset.change(availability: :missing) |> Repo.update!()
    assert {:ok, episodes} = Catalog.list_episodes(@actor, season.id, 1)
    assert hd(episodes.items).available_version_count == 1
    assert {:ok, %{total: 2, items: []}} = Catalog.list_episodes(@actor, season.id, 2)
  end

  test "library series counts include only its identified episodes without duplicates" do
    first = SeriesFixtures.library()
    second = SeriesFixtures.library()
    SeriesFixtures.identify(SeriesFixtures.file(first.id, "S01E01E02.mkv"), 1, [1, 2])
    SeriesFixtures.identify(SeriesFixtures.file(first.id, "S01E01.mp4"), 1, [1])
    SeriesFixtures.identify(SeriesFixtures.file(second.id, "S00E01.mkv"), 0, [1])
    assert {:ok, %{total: 1, items: [item]}} = Catalog.search_series(@actor, "", 1, first.id)
    assert item.episode_count == 2
    assert item.available_episode_count == 2
    assert {:ok, %{items: [other]}} = Catalog.search_series(@actor, "", 1, second.id)
    assert other.episode_count == 1
    empty = SeriesFixtures.library()
    assert {:ok, %{total: 0, items: []}} = Catalog.search_series(@actor, "", 1, empty.id)
    assert {:ok, %{total: 1, items: []}} = Catalog.search_series(@actor, "", 2, first.id)
    assert {:error, :forbidden} = Catalog.search_series(nil, "", 1, first.id)
    assert {:error, :invalid_query} = Catalog.search_series(@actor, "", 1, "bad")
  end

  test "movie and series resources with the same external ID remain separate" do
    library = SeriesFixtures.library()
    file = SeriesFixtures.file(library.id, "Serie S01E01.mkv")
    SeriesFixtures.identify(file, 1, [1])

    identity =
      Repo.insert!(%CatalogEntrySchema{
        kind: :movie,
        provider: :tmdb,
        resource_type: :movie,
        provider_id: 201
      })

    Repo.insert!(%MovieSchema{id: identity.id, title: "Movie"})
    assert {:ok, %{total: 1}} = Catalog.search_series(@actor, "", 1)
    assert {:ok, %{total: 1}} = Catalog.list_movies(@actor, "", 1)
  end

  test "queries authorize validate and distinguish empty pages from missing parents" do
    assert {:error, :forbidden} = Catalog.search_series(nil, "", 1)
    assert {:error, :invalid_query} = Catalog.search_series(@actor, String.duplicate("x", 257), 1)
    assert {:error, :invalid_page} = Catalog.search_series(@actor, "", 0)
    assert {:ok, %{items: [], total: 0}} = Catalog.search_series(@actor, "", 1)
    assert {:error, :not_found} = Catalog.get_series(@actor, 9_999_999)
    assert {:error, :not_found} = Catalog.get_episode(@actor, 9_999_999)
    assert {:error, :not_found} = Catalog.list_episodes(@actor, 9_999_999, 1)
  end

  test "episode versions expose only technical data for the current revision" do
    library = SeriesFixtures.library()
    file = SeriesFixtures.file(library.id, "Serie S01E01.mkv")
    decision = SeriesFixtures.identify(file, 1, [1])

    inspection =
      Repo.insert!(%InspectionSchema{
        media_file_id: file.id,
        token: Ecto.UUID.generate(),
        observed_revision: file.revision,
        state: :succeeded,
        format: "matroska",
        duration_ms: 120_000,
        tracks: %{
          "items" => [
            %{"kind" => "video", "codec" => "h264"},
            %{"kind" => "audio", "codec" => "ac3"}
          ]
        }
      })

    assert {:ok, %{versions: [version]}} =
             Catalog.get_episode(@actor, hd(decision.catalog_entry_ids))

    assert version.format == "matroska"
    assert version.duration_ms == 120_000
    assert version.codecs == ["h264", "ac3"]
    Repo.update!(Ecto.Changeset.change(inspection, observed_revision: file.revision + 1))

    assert {:ok, %{versions: [version]}} =
             Catalog.get_episode(@actor, hd(decision.catalog_entry_ids))

    assert version.format == nil
    assert version.codecs == []
  end
end
