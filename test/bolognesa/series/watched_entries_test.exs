defmodule Bolognesa.Series.WatchedEntriesTest do
  use Bolognesa.DataCase, async: true
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Infrastructure.Persistence.SeriesWatchedEntrySchema
  alias Bolognesa.Infrastructure.Persistence.UserSchema
  alias Bolognesa.Libraries.Domain.ValueObjects.Files.NewMediaFile
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoScanRepository
  alias Bolognesa.Series
  alias Bolognesa.Series.Application.UseCases.RecordWatchedEntries
  alias Bolognesa.Series.Domain.ValueObjects.SeasonEntry
  alias Bolognesa.Series.Infrastructure.Readers.EctoWatchedEntriesReader, as: Reader
  alias Bolognesa.Series.Infrastructure.Repositories.EctoWatchedEntriesRepository, as: Repository
  alias Bolognesa.SeriesFixtures
  alias Ecto.Changeset

  defmodule FailingRepository do
    @behaviour Bolognesa.Series.Application.Ports.Repositories.WatchedEntriesRepository
    @impl true
    def upsert(_, _, _), do: {:error, :unavailable}
    @impl true
    def delete(_, _), do: {:error, :unavailable}
  end

  setup do
    user =
      Repo.insert!(%UserSchema{
        name: "Viewer",
        email: "viewer@example.com",
        hashed_password: "hash",
        role: "admin"
      })

    other =
      Repo.insert!(%UserSchema{
        name: "Other",
        email: "other@example.com",
        hashed_password: "hash",
        role: "member"
      })

    library = SeriesFixtures.library()
    file = SeriesFixtures.file(library.id, "Example S01E01.mp4")
    [episode_id] = SeriesFixtures.identify(file, 1, [1]).episode_ids

    {:ok, detail} =
      Series.fetch_episode(%AuthenticatedUser{id: user.id, role: :admin}, episode_id)

    %{
      actor: %AuthenticatedUser{id: user.id, role: :admin},
      other: other,
      media_file: file,
      library: library,
      episode_id: episode_id,
      season_id: detail.season.id,
      series_id: detail.series.id,
      entry: %SeasonEntry{episode_id: episode_id, part_number: nil}
    }
  end

  test "failed persistence emits a sanitized watched-entry failure observation", ctx do
    reference = make_ref()
    owner = self()
    event = [:bolognesa, :series, :watched_entries, :failed]

    :ok =
      :telemetry.attach(
        reference,
        event,
        fn name, measurements, metadata, _ ->
          send(owner, {name, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(reference) end)

    assert {:error, :unavailable} =
             RecordWatchedEntries.call(
               ctx.actor,
               ctx.episode_id,
               ctx.media_file.id,
               Reader,
               FailingRepository
             )

    assert_receive {^event, %{count: 1}, metadata}
    assert metadata == %{user_id: ctx.actor.id, file_id: ctx.media_file.id, reason: :unavailable}
  end

  test "unassociated and missing files cannot record watched entries", ctx do
    unrelated = SeriesFixtures.file(ctx.library.id, "Example S01E02.mp4")
    SeriesFixtures.identify(unrelated, 1, [2])

    assert {:error, :not_found} =
             Series.record_watched_entries(ctx.actor, ctx.episode_id, unrelated.id)

    assert {:ok, []} = Series.list_watched_entries(ctx.actor, {:series, ctx.series_id})

    ctx.media_file |> Changeset.change(availability: :missing) |> Repo.update!()

    assert {:error, :not_found} =
             Series.record_watched_entries(ctx.actor, ctx.episode_id, ctx.media_file.id)

    assert {:ok, []} = Series.list_watched_entries(ctx.actor, {:series, ctx.series_id})
  end

  test "latest timestamp wins for nil and numbered parts, with account-scoped reads",
       ctx do
    earlier = ~U[2026-01-01 00:00:00.000000Z]
    later = ~U[2026-02-01 00:00:00.000000Z]
    part = %{ctx.entry | part_number: 1}
    assert :ok = Repository.upsert(ctx.actor.id, [ctx.entry, part], later)
    assert :ok = Repository.upsert(ctx.actor.id, [ctx.entry, part], earlier)
    assert :ok = Repository.upsert(ctx.other.id, [ctx.entry], earlier)

    for scope <- [
          {:episode, ctx.episode_id},
          {:season, ctx.season_id},
          {:series, ctx.series_id}
        ] do
      assert {:ok, entries} = Series.list_watched_entries(ctx.actor, scope)
      assert Enum.map(entries, & &1.season_entry) == [ctx.entry, part]
      assert Enum.all?(entries, &(&1.last_watched_at == later))
    end

    assert {:ok, [%{last_watched_at: ^earlier}]} =
             Reader.list_watched_entries(ctx.other.id, {:episode, ctx.episode_id})

    assert {:error, :forbidden} = Series.list_watched_entries(nil, {:episode, ctx.episode_id})
  end

  test "season episode items carry the account's watched date per entry", ctx do
    second = SeriesFixtures.file(ctx.library.id, "Example S01E02.mp4")
    SeriesFixtures.identify(second, 1, [2])
    watched_at = ~U[2026-02-01 00:00:00.000000Z]
    assert :ok = Repository.upsert(ctx.actor.id, [ctx.entry], watched_at)

    assert {:ok, page} = Series.list_episodes(ctx.actor, ctx.season_id, 1)
    assert Enum.map(page.items, &{&1.number, &1.watched_at}) == [{1, watched_at}, {2, nil}]
  end

  test "upsert uses the NULLS NOT DISTINCT index for an unsplit entry", ctx do
    earlier = ~U[2026-01-01 00:00:00.000000Z]
    later = ~U[2026-02-01 00:00:00.000000Z]
    assert :ok = Repository.upsert(ctx.actor.id, [ctx.entry], earlier)
    assert :ok = Repository.upsert(ctx.actor.id, [ctx.entry], later)
    assert :ok = Repository.upsert(ctx.actor.id, [ctx.entry], earlier)

    assert Repo.all(
             from row in SeriesWatchedEntrySchema,
               where: row.user_id == ^ctx.actor.id,
               select: {row.episode_id, row.part_number, row.last_watched_at}
           ) ==
             [{ctx.episode_id, nil, later}]
  end

  test "played files resolve a single part, every whole-file part, and every associated episode",
       ctx do
    first = SeriesFixtures.file(ctx.library.id, "Example S01E01-part1.mp4")
    second = SeriesFixtures.file(ctx.library.id, "Example S01E01-part2.mp4")
    SeriesFixtures.identify(first, 1, [1])
    SeriesFixtures.identify(second, 1, [1])
    second |> Changeset.change(availability: :missing) |> Repo.update!()

    assert {:ok, [%SeasonEntry{part_number: 1}]} =
             Reader.fetch_played_entries(ctx.episode_id, first.id)

    assert {:ok, entries} = Reader.fetch_played_entries(ctx.episode_id, ctx.media_file.id)
    assert Enum.map(entries, & &1.part_number) == [1, 2]
    multi = SeriesFixtures.file(ctx.library.id, "Example S01E01E02.mp4")
    decision = SeriesFixtures.identify(multi, 1, [1, 2])
    assert {:ok, entries} = Reader.fetch_played_entries(ctx.episode_id, multi.id)

    assert Enum.map(entries, &{&1.episode_id, &1.part_number}) ==
             [{ctx.episode_id, 1}, {ctx.episode_id, 2}, {List.last(decision.episode_ids), nil}]

    assert {:error, :not_found} = Reader.fetch_played_entries(ctx.episode_id, -1)
  end

  test "watched state survives inventory revision, missing files, rename, replacement and correction",
       ctx do
    assert :ok = Repository.upsert(ctx.actor.id, [ctx.entry], DateTime.utc_now())
    ctx.media_file |> Changeset.change(revision: 2, availability: :missing) |> Repo.update!()
    renamed = SeriesFixtures.file(ctx.library.id, "Renamed S01E01.mp4")
    SeriesFixtures.identify(renamed, 1, [1])
    renamed |> Changeset.change(revision: 2, size_bytes: 100) |> Repo.update!()
    SeriesFixtures.identify(renamed, 1, [2])

    assert {:ok, [%{season_entry: %SeasonEntry{episode_id: id}}]} =
             Series.list_watched_entries(ctx.actor, {:series, ctx.series_id})

    assert id == ctx.episode_id
  end

  test "completed rescans preserve watched state when inventory disappears, returns or is replaced",
       ctx do
    assert :ok = Repository.upsert(ctx.actor.id, [ctx.entry], DateTime.utc_now())

    original = %NewMediaFile{
      relative_path: ctx.media_file.relative_path,
      size_bytes: ctx.media_file.size_bytes,
      modified_at: ctx.media_file.modified_at
    }

    for entries <- [[original], [], [original], [%{original | size_bytes: 100}]] do
      assert {:ok, scan} = EctoScanRepository.request(ctx.library.id)
      assert {:ok, running, _} = EctoScanRepository.begin_attempt(scan.id, 1)
      assert {:ok, _} = EctoScanRepository.save_batch(scan.id, running.generation, entries)
      assert {:ok, _} = EctoScanRepository.complete(scan.id, running.generation)

      assert {:ok, [%{season_entry: %SeasonEntry{episode_id: id}}]} =
               Series.list_watched_entries(ctx.actor, {:episode, ctx.episode_id})

      assert id == ctx.episode_id
    end
  end

  test "empty writes are no-ops", ctx do
    assert :ok = Repository.upsert(ctx.actor.id, [], DateTime.utc_now())
    assert {:ok, []} = Reader.list_watched_entries(ctx.actor.id, {:series, ctx.series_id})
  end

  test "batch writes roll back on invalid episode references and nil keys are unique", ctx do
    invalid = %SeasonEntry{episode_id: 999_999_999, part_number: nil}

    assert {:error, :unavailable} =
             Repository.upsert(ctx.actor.id, [ctx.entry, invalid], DateTime.utc_now())

    assert {:ok, []} = Reader.list_watched_entries(ctx.actor.id, {:episode, ctx.episode_id})
    assert :ok = Repository.upsert(ctx.actor.id, [ctx.entry, ctx.entry], DateTime.utc_now())
    assert {:ok, [_]} = Reader.list_watched_entries(ctx.actor.id, {:episode, ctx.episode_id})
  end

  test "marking an entry sets it watched now and unmarking deletes only that account's row",
       ctx do
    before = DateTime.utc_now()
    assert :ok = Series.mark_entries_watched(ctx.actor, {:entry, ctx.entry})

    assert {:ok, [%{season_entry: entry, last_watched_at: at}]} =
             Series.list_watched_entries(ctx.actor, {:episode, ctx.episode_id})

    assert entry == ctx.entry
    assert DateTime.compare(at, before) != :lt

    assert :ok = Repository.upsert(ctx.other.id, [ctx.entry], at)
    assert :ok = Series.unmark_entry_watched(ctx.actor, ctx.entry)
    assert :ok = Series.unmark_entry_watched(ctx.actor, ctx.entry)
    assert {:ok, []} = Series.list_watched_entries(ctx.actor, {:episode, ctx.episode_id})
    assert {:ok, [_]} = Reader.list_watched_entries(ctx.other.id, {:episode, ctx.episode_id})
  end

  test "marking an unknown entry or season records nothing", ctx do
    unknown = %{ctx.entry | part_number: 3}
    assert {:error, :not_found} = Series.mark_entries_watched(ctx.actor, {:entry, unknown})
    assert {:error, :not_found} = Series.mark_entries_watched(ctx.actor, {:season, 0})
    assert {:ok, []} = Series.list_watched_entries(ctx.actor, {:series, ctx.series_id})
  end

  test "marking a season includes unavailable entries and requires an admin", ctx do
    missing = SeriesFixtures.file(ctx.library.id, "Example S01E02.mp4")
    [missing_id] = SeriesFixtures.identify(missing, 1, [2]).episode_ids
    missing |> Changeset.change(availability: :missing) |> Repo.update!()

    assert {:error, :forbidden} =
             Series.mark_entries_watched(%{ctx.actor | role: :member}, {:season, ctx.season_id})

    assert :ok = Series.mark_entries_watched(ctx.actor, {:season, ctx.season_id})
    assert {:ok, entries} = Series.list_watched_entries(ctx.actor, {:season, ctx.season_id})
    assert Enum.map(entries, & &1.season_entry.episode_id) == [ctx.episode_id, missing_id]
  end
end
