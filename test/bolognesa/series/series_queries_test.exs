defmodule Bolognesa.Series.SeriesQueriesTest do
  use Bolognesa.DataCase, async: false
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Infrastructure.Persistence.InspectionSchema
  alias Bolognesa.Infrastructure.Persistence.MovieSchema
  alias Bolognesa.Series
  alias Bolognesa.SeriesFixtures
  @actor %AuthenticatedUser{id: 1, role: :admin}

  test "next episode skips the completed file and missing versions across seasons" do
    library = SeriesFixtures.library()
    first = SeriesFixtures.file(library.id, "double.mkv")
    decision = SeriesFixtures.identify(first, 1, [1, 2])
    missing = SeriesFixtures.file(library.id, "missing.mkv")
    SeriesFixtures.identify(missing, 2, [1])
    missing |> Ecto.Changeset.change(availability: :missing) |> Repo.update!()
    next = SeriesFixtures.file(library.id, "next.mkv")
    next_decision = SeriesFixtures.identify(next, 2, [2])

    assert {:ok, episode} =
             Series.fetch_next_available_episode(@actor, hd(decision.episode_ids), first.id)

    assert episode.id == hd(next_decision.episode_ids)
    assert :not_found = Series.fetch_next_available_episode(@actor, episode.id, next.id)
    assert :not_found = Series.fetch_next_available_episode(@actor, episode.id, first.id)
    assert {:error, :forbidden} = Series.fetch_next_available_episode(nil, episode.id, next.id)
  end

  test "next episode follows episode number within the same season" do
    library = SeriesFixtures.library()
    later = SeriesFixtures.file(library.id, "later.mkv")
    later_decision = SeriesFixtures.identify(later, 1, [2])
    earlier = SeriesFixtures.file(library.id, "earlier.mkv")
    earlier_decision = SeriesFixtures.identify(earlier, 1, [1])

    assert {:ok, episode} =
             Series.fetch_next_available_episode(
               @actor,
               hd(earlier_decision.episode_ids),
               earlier.id
             )

    assert episode.id == hd(later_decision.episode_ids)
    assert :not_found = Series.fetch_next_available_episode(@actor, episode.id, later.id)
  end

  test "detail neighbors use episode order rather than insertion order and stay in the season" do
    library = SeriesFixtures.library()
    later = SeriesFixtures.file(library.id, "later.mkv")
    [later_id] = SeriesFixtures.identify(later, 1, [2]).episode_ids
    earlier = SeriesFixtures.file(library.id, "earlier.mkv")
    [earlier_id] = SeriesFixtures.identify(earlier, 1, [1]).episode_ids
    other = SeriesFixtures.file(library.id, "other.mkv")
    SeriesFixtures.identify(other, 2, [1])

    assert {:ok, %{previous_episode_id: nil, next_episode_id: ^later_id}} =
             Series.fetch_episode(@actor, earlier_id)

    assert {:ok, %{previous_episode_id: ^earlier_id, next_episode_id: nil}} =
             Series.fetch_episode(@actor, later_id)
  end

  test "episode detail query count stays constant as physical versions increase" do
    library = SeriesFixtures.library()
    first = SeriesFixtures.file(library.id, "first.mkv")
    decision = SeriesFixtures.identify(first, 1, [1, 2])
    episode_id = hd(decision.episode_ids)

    {initial, initial_queries} = count_queries(fn -> Series.fetch_episode(@actor, episode_id) end)
    assert {:ok, %{versions: [%{id: first_id, episode_numbers: [1, 2]}]}} = initial
    assert first_id == first.id

    second = SeriesFixtures.file(library.id, "second.mkv")
    SeriesFixtures.identify(second, 1, [1])
    third = SeriesFixtures.file(library.id, "third.mkv")
    SeriesFixtures.identify(third, 1, [1, 2])

    {expanded, expanded_queries} =
      count_queries(fn -> Series.fetch_episode(@actor, episode_id) end)

    assert {:ok, %{versions: versions}} = expanded

    assert Enum.map(versions, &{&1.id, &1.episode_numbers}) ==
             [{first.id, [1, 2]}, {second.id, [1]}, {third.id, [1, 2]}]

    assert initial_queries > 0
    assert expanded_queries == initial_queries
  end

  test "groups versions and multi episode files without inflating catalog counts" do
    library = SeriesFixtures.library()
    double = SeriesFixtures.file(library.id, "Serie S00E01E02.mkv")
    decision = SeriesFixtures.identify(double, 0, [1, 2])
    single = SeriesFixtures.file(library.id, "Serie S00E01.mp4")
    SeriesFixtures.identify(single, 0, [1])
    assert {:ok, page} = Series.search_series(@actor, "Serie", 1)
    assert page.total == 1
    assert [item] = page.items
    assert item.episode_count == 2
    assert {:ok, detail} = Series.fetch_series(@actor, item.id)
    assert [%{number: 0, episode_count: 2} = season] = detail.seasons
    assert {:ok, episodes} = Series.list_episodes(@actor, season.id, 1)
    assert Enum.map(episodes.items, & &1.number) == [1, 2]
    assert hd(episodes.items).version_count == 2
    assert {:ok, episode} = Series.fetch_episode(@actor, hd(decision.episode_ids))
    assert episode.series.title == "Serie"
    assert length(episode.versions) == 2
    assert Enum.map(episode.versions, & &1.episode_numbers) == [[1, 2], [1]]
    single |> Ecto.Changeset.change(availability: :missing) |> Repo.update!()
    assert {:ok, episodes} = Series.list_episodes(@actor, season.id, 1)
    assert hd(episodes.items).available_version_count == 1
    assert {:ok, %{total: 2, items: []}} = Series.list_episodes(@actor, season.id, 2)
  end

  test "library series counts include only its identified episodes without duplicates" do
    first = SeriesFixtures.library()
    second = SeriesFixtures.library()
    SeriesFixtures.identify(SeriesFixtures.file(first.id, "S01E01E02.mkv"), 1, [1, 2])
    SeriesFixtures.identify(SeriesFixtures.file(first.id, "S01E01.mp4"), 1, [1])
    SeriesFixtures.identify(SeriesFixtures.file(second.id, "S00E01.mkv"), 0, [1])
    assert {:ok, %{total: 1, items: [item]}} = Series.search_series(@actor, "", 1, first.id)
    assert item.episode_count == 2
    assert item.available_episode_count == 2
    assert {:ok, %{items: [other]}} = Series.search_series(@actor, "", 1, second.id)
    assert other.episode_count == 1
    empty = SeriesFixtures.library()
    assert {:ok, %{total: 0, items: []}} = Series.search_series(@actor, "", 1, empty.id)
    assert {:ok, %{total: 1, items: []}} = Series.search_series(@actor, "", 2, first.id)
    assert {:error, :forbidden} = Series.search_series(nil, "", 1, first.id)
    assert {:error, :invalid_query} = Series.search_series(@actor, "", 1, "bad")
  end

  test "movie and series resources with the same external ID remain separate" do
    library = SeriesFixtures.library()
    file = SeriesFixtures.file(library.id, "Serie S01E01.mkv")
    SeriesFixtures.identify(file, 1, [1])

    Repo.insert!(%MovieSchema{provider: :tmdb, provider_id: 201, title: "Movie"})
    assert {:ok, %{total: 1}} = Series.search_series(@actor, "", 1)
    assert {:ok, %{total: 1}} = Bolognesa.Movies.list_movies(@actor, "", 1)
  end

  test "queries authorize validate and distinguish empty pages from missing parents" do
    assert {:error, :forbidden} = Series.search_series(nil, "", 1)
    assert {:error, :invalid_query} = Series.search_series(@actor, String.duplicate("x", 257), 1)
    assert {:error, :invalid_page} = Series.search_series(@actor, "", 0)
    assert {:ok, %{items: [], total: 0}} = Series.search_series(@actor, "", 1)
    assert {:error, :forbidden} = Series.fetch_series(nil, 1)
    assert {:error, :forbidden} = Series.fetch_episode(nil, 1)
    assert :not_found = Series.fetch_series(@actor, 0)
    assert :not_found = Series.fetch_episode(@actor, "invalid")
    assert :not_found = Series.fetch_series(@actor, 9_999_999)
    assert :not_found = Series.fetch_episode(@actor, 9_999_999)
    assert {:error, :not_found} = Series.list_episodes(@actor, 9_999_999, 1)
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
             Series.fetch_episode(@actor, hd(decision.episode_ids))

    assert version.format == "matroska"
    assert version.duration_ms == 120_000
    assert version.codecs == ["h264", "ac3"]
    Repo.update!(Ecto.Changeset.change(inspection, observed_revision: file.revision + 1))

    assert {:ok, %{versions: [version]}} =
             Series.fetch_episode(@actor, hd(decision.episode_ids))

    assert version.format == nil
    assert version.codecs == []
  end

  test "episode details reject more than one hundred versions" do
    library = SeriesFixtures.library()
    first = SeriesFixtures.identify(SeriesFixtures.file(library.id, "version-1.mkv"), 1, [1])
    episode_id = hd(first.episode_ids)

    for index <- 2..100 do
      SeriesFixtures.identify(SeriesFixtures.file(library.id, "version-#{index}.mkv"), 1, [1])
    end

    assert {:ok, %{versions: versions}} = Series.fetch_episode(@actor, episode_id)
    assert length(versions) == 100
    SeriesFixtures.identify(SeriesFixtures.file(library.id, "version-101.mkv"), 1, [1])
    assert {:error, :too_many_versions} = Series.fetch_episode(@actor, episode_id)
  end

  test "series details reject more than one hundred seasons" do
    library = SeriesFixtures.library()
    decision = SeriesFixtures.identify(SeriesFixtures.file(library.id, "first.mkv"), 1, [1])
    assert {:ok, detail} = Series.fetch_episode(@actor, hd(decision.episode_ids))
    series_id = detail.series.id

    for number <- 2..100 do
      Repo.insert!(%Bolognesa.Infrastructure.Persistence.SeasonSchema{
        series_id: series_id,
        provider: :tmdb,
        provider_id: 100_000 + number,
        number: number
      })
    end

    assert {:ok, %{seasons: seasons}} = Series.fetch_series(@actor, series_id)
    assert length(seasons) == 100

    Repo.insert!(%Bolognesa.Infrastructure.Persistence.SeasonSchema{
      series_id: series_id,
      provider: :tmdb,
      provider_id: 100_101,
      number: 101
    })

    assert {:error, :too_many_seasons} = Series.fetch_series(@actor, series_id)
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
