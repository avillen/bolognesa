defmodule Bolognesa.Libraries.ScanInventoryTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Infrastructure.Persistence.InspectionEventSchema
  alias Bolognesa.Infrastructure.Persistence.InspectionSchema
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.MovieIdentificationEventSchema
  alias Bolognesa.Infrastructure.Persistence.MovieIdentificationSchema
  alias Bolognesa.Infrastructure.Persistence.ScanSchema
  alias Bolognesa.Libraries.Application.UseCases.DiscoverFiles
  alias Bolognesa.Libraries.Domain.ValueObjects.Files.NewMediaFile
  alias Bolognesa.Libraries.Domain.ValueObjects.Inspection.TechnicalMedia
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoInspectionRepository
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoOutboxRepository
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoScanRepository
  alias Bolognesa.Libraries.Infrastructure.Services.LibraryStatusNotifications
  alias Bolognesa.Libraries.Support.ControlledFileDiscovery
  alias Ecto.Adapters.SQL
  alias EctoScanRepository.MediaFileMapper
  alias EctoScanRepository.ScanMapper
  alias SQL.Sandbox

  @modified ~U[2026-10-03 00:00:00Z]

  @tag committed: true
  test "application scan hints expose committed completion to another connection" do
    parent = self()
    supervisor = start_supervised!(Task.Supervisor)
    :ok = Phoenix.PubSub.subscribe(Bolognesa.PubSub, "libraries:statuses")

    with_committed_scan(fn scan ->
      library_id = scan.library_id
      refute_receive {:library_status_changed, _}

      scanner =
        Task.Supervisor.async_nolink(supervisor, fn ->
          Sandbox.unboxed_run(Repo, fn ->
            ControlledFileDiscovery.configure(parent)

            DiscoverFiles.call(
              scan.id,
              1,
              EctoScanRepository,
              ControlledFileDiscovery,
              LibraryStatusNotifications
            )
          end)
        end)

      assert_receive {:walking, scanner_pid}
      assert_receive {:library_status_changed, ^library_id}
      send(scanner_pid, {:batch, [entry("a.mp4")]})
      assert_receive {:batch_result, ^scanner_pid, :ok}
      assert_receive {:library_status_changed, ^library_id}

      reader =
        Task.Supervisor.async_nolink(supervisor, fn ->
          Sandbox.unboxed_run(Repo, fn ->
            :ok = Phoenix.PubSub.subscribe(Bolognesa.PubSub, "libraries:statuses")
            send(parent, :status_reader_ready)

            receive do
              {:library_status_changed, ^library_id} ->
                EctoScanRepository.fetch_status(library_id)
            end
          end)
        end)

      assert_receive :status_reader_ready
      send(scanner_pid, {:finish, :ok})
      assert :ok = Task.await(scanner)
      assert_receive {:library_status_changed, ^library_id}
      assert {:ok, %{latest_scan: %{state: :completed, files_discovered: 1}}} = Task.await(reader)
      assert {:ok, :terminal} = EctoScanRepository.begin_attempt(scan.id, 2)
      refute_receive {:library_status_changed, _}
    end)
  end

  test "persisting scan progress does not publish interface notifications", %{scan: scan} do
    :ok = Phoenix.PubSub.subscribe(Bolognesa.PubSub, "libraries:statuses")
    running = start(scan)
    save(running, [entry("a.mp4")])
    assert {:ok, _} = EctoScanRepository.complete(scan.id, running.generation)
    refute_receive {:library_status_changed, _}

    assert {:ok, %{latest_scan: %{state: :completed, files_discovered: 1}}} =
             EctoScanRepository.fetch_status(scan.library_id)
  end

  @tag committed: true
  test "scan recovery reports earlier commits when a later transaction fails" do
    library_ids =
      with_committed_scans(2, fn [first, second] ->
        for scan <- [first, second] do
          Repo.get!(Oban.Job, scan.job_id)
          |> Ecto.Changeset.change(state: "discarded")
          |> Repo.update!()
        end

        SQL.query!(Repo, """
        ALTER TABLE library_scans ADD CONSTRAINT notification_test_reject_scan_recovery
        CHECK (id <> #{second.id} OR state <> 'failed') NOT VALID
        """)

        try do
          :ok = Phoenix.PubSub.subscribe(Bolognesa.PubSub, "libraries:statuses")
          result = EctoScanRepository.reconcile_jobs(DateTime.utc_now())
          assert result.error == :unavailable
          assert result.changed_library_ids == [first.library_id]
          assert stored_scan(first.id).state == :failed
          assert stored_scan(second.id).state == :queued
          refute_receive {:library_status_changed, _}
        after
          SQL.query!(
            Repo,
            "ALTER TABLE library_scans DROP CONSTRAINT notification_test_reject_scan_recovery"
          )
        end

        [first.library_id, second.library_id]
      end)

    assert_committed_fixtures_removed(library_ids)
  end

  @tag committed: true
  test "inspection recovery reports earlier commits when a later transaction fails" do
    library_ids =
      with_committed_scans(2, fn [first, second] ->
        for scan <- [first, second], do: save(start(scan), [entry("a.mp4")])

        assert {:ok, 2} =
                 EctoOutboxRepository.dispatch_batch(25)

        [first_file] = files(first.library_id)
        [second_file] = files(second.library_id)
        first_inspection = inspection(first_file.id)
        second_inspection = inspection(second_file.id)
        job_ids = [first_inspection.job_id, second_inspection.job_id]

        for id <- job_ids do
          Repo.get!(Oban.Job, id) |> Ecto.Changeset.change(state: "discarded") |> Repo.update!()
        end

        SQL.query!(Repo, """
        ALTER TABLE media_inspections ADD CONSTRAINT notification_test_reject_inspection_recovery
        CHECK (id <> #{second_inspection.id} OR state <> 'failed') NOT VALID
        """)

        try do
          :ok = Phoenix.PubSub.subscribe(Bolognesa.PubSub, "libraries:statuses")
          result = EctoInspectionRepository.reconcile_jobs(DateTime.utc_now())
          assert result.error == :unavailable
          assert result.changed_library_ids == [first.library_id]
          assert inspection(first_file.id).state == :failed
          assert inspection(second_file.id).state == :pending
          refute_receive {:library_status_changed, _}
        after
          SQL.query!(
            Repo,
            "ALTER TABLE media_inspections DROP CONSTRAINT notification_test_reject_inspection_recovery"
          )

          Repo.delete_all(from job in Oban.Job, where: job.id in ^job_ids)
        end

        [first.library_id, second.library_id]
      end)

    assert_committed_fixtures_removed(library_ids)
  end

  setup context do
    case context[:committed] do
      true ->
        :ok

      _ ->
        library = library_fixture()
        {:ok, scan} = EctoScanRepository.request(library.id)
        %{library: library, scan: scan}
    end
  end

  test "rejects old batches and counts repeated batches once", %{scan: scan} do
    assert {:ok, old, _} = EctoScanRepository.begin_attempt(scan.id, 1)
    assert {:ok, current, _} = EctoScanRepository.begin_attempt(scan.id, 1)
    entry = entry("a.mp4")

    assert old.generation != current.generation
    :ok = Phoenix.PubSub.subscribe(Bolognesa.PubSub, "libraries:statuses")

    assert {:error, :stale_attempt} =
             EctoScanRepository.save_batch(scan.id, old.generation, [entry])

    refute_receive {:library_status_changed, _}

    assert {:ok, saved = %{files_discovered: 1}} =
             EctoScanRepository.save_batch(scan.id, current.generation, [entry, entry])

    assert DateTime.compare(saved.updated_at, current.updated_at) == :gt

    assert {:ok, %{files_discovered: 1}} =
             EctoScanRepository.save_batch(scan.id, current.generation, [entry])

    assert [file] = files(current.library_id)
    assert file.revision == 1
    assert file.last_seen_generation == current.generation
  end

  test "existing scans default to normal inspection mode", %{scan: scan} do
    assert stored_scan(scan.id).force_inspection? == false
  end

  test "requests identification once for a new file and again on revision change", %{scan: scan} do
    running = start(scan)
    save(running, [entry("a.mp4")])
    [file] = files(scan.library_id)
    first = Repo.get_by!(MovieIdentificationSchema, media_file_id: file.id)
    assert first.state == :pending
    assert first.observed_revision == 1
    assert [_event] = identification_events(file.id)

    save(running, [entry("a.mp4")])
    assert Repo.get_by!(MovieIdentificationSchema, media_file_id: file.id).token == first.token
    assert length(identification_events(file.id)) == 1
    assert {:ok, _} = EctoScanRepository.complete(scan.id, running.generation)

    unchanged = next_scan(scan.library_id)
    save(unchanged, [entry("a.mp4")])
    assert length(identification_events(file.id)) == 1
    assert {:ok, _} = EctoScanRepository.complete(unchanged.id, unchanged.generation)

    changed = next_scan(scan.library_id)
    save(changed, [entry("a.mp4", 6)])
    second = Repo.get_by!(MovieIdentificationSchema, media_file_id: file.id)
    assert second.observed_revision == 2
    refute second.token == first.token
    assert length(identification_events(file.id)) == 2
    assert {:ok, _} = EctoScanRepository.complete(changed.id, changed.generation)

    absent = next_scan(scan.library_id)
    assert {:ok, _} = EctoScanRepository.complete(absent.id, absent.generation)
    restored = next_scan(scan.library_id)
    save(restored, [entry("a.mp4", 6)])
    assert length(identification_events(file.id)) == 3
  end

  @tag committed: true
  test "rolls back inventory when identification event cannot be stored" do
    with_committed_scan(fn scan ->
      running = start(scan)
      existing = entry("existing.mp4")
      save(running, [existing])
      [file] = files(scan.library_id)
      before = stored_scan(scan.id)

      SQL.query!(Repo, """
      ALTER TABLE movie_identification_events ADD CONSTRAINT inventory_test_reject_identification
      CHECK (media_file_id <> #{file.id}) NOT VALID
      """)

      try do
        :ok = Phoenix.PubSub.subscribe(Bolognesa.PubSub, "libraries:statuses")

        assert {:error, :unavailable} =
                 EctoScanRepository.save_batch(scan.id, running.generation, [
                   entry("existing.mp4", 6),
                   entry("new.mp4")
                 ])

        refute_receive {:library_status_changed, _}

        assert [unchanged] = files(scan.library_id)
        assert unchanged.revision == file.revision
        assert stored_scan(scan.id) == before
        assert length(identification_events(file.id)) == 1
      after
        SQL.query!(
          Repo,
          "ALTER TABLE movie_identification_events DROP CONSTRAINT inventory_test_reject_identification"
        )
      end
    end)
  end

  test "series handoff failure rolls back inventory inspection requests and owner events" do
    with_committed_scan(fn scan ->
      library = Repo.get!(LibrarySchema, scan.library_id)
      Repo.update!(Ecto.Changeset.change(library, content_type: :series))
      running = start(scan)
      save(running, [entry("existing.mkv")])
      [file] = files(scan.library_id)

      decision =
        Repo.get_by!(Bolognesa.Infrastructure.Persistence.SeriesIdentificationSchema,
          media_file_id: file.id
        )

      before = stored_scan(scan.id)

      SQL.query!(
        Repo,
        "ALTER TABLE series_identification_events ADD CONSTRAINT inventory_test_reject_series CHECK (media_file_id <> #{file.id}) NOT VALID"
      )

      try do
        assert {:error, :unavailable} =
                 EctoScanRepository.save_batch(scan.id, running.generation, [
                   entry("existing.mkv", 6),
                   entry("new.mkv")
                 ])

        assert [unchanged] = files(scan.library_id)
        assert unchanged.revision == file.revision
        assert stored_scan(scan.id) == before
        assert length(events(file.id)) == 1

        assert Repo.get_by!(Bolognesa.Infrastructure.Persistence.SeriesIdentificationSchema,
                 media_file_id: file.id
               ) == decision

        assert Repo.aggregate(
                 Bolognesa.Infrastructure.Persistence.SeriesIdentificationEventSchema,
                 :count
               ) == 1

        assert Repo.aggregate(MovieIdentificationSchema, :count) == 0
      after
        SQL.query!(
          Repo,
          "ALTER TABLE series_identification_events DROP CONSTRAINT inventory_test_reject_series"
        )
      end
    end)
  end

  test "preserves manual identification after file changes", %{scan: scan} do
    running = start(scan)
    save(running, [entry("a.mp4")])
    [file] = files(scan.library_id)
    first = Repo.get_by!(MovieIdentificationSchema, media_file_id: file.id)

    first
    |> MovieIdentificationSchema.changeset(%{state: :manual_unidentified, origin: :manual})
    |> Repo.update!()

    assert {:ok, _} = EctoScanRepository.complete(scan.id, running.generation)
    changed = next_scan(scan.library_id)
    save(changed, [entry("a.mp4", 6)])
    current = Repo.get_by!(MovieIdentificationSchema, media_file_id: file.id)
    assert current.state == :manual_unidentified
    assert current.token == first.token
    assert length(identification_events(file.id)) == 1
  end

  test "stores one technical state per file and one event per token", %{scan: scan} do
    running = start(scan)
    save(running, [entry("a.mp4")])
    [file] = files(scan.library_id)
    token = inspection(file.id).token

    attrs = %{
      media_file_id: file.id,
      token: token,
      observed_revision: file.revision,
      state: :pending
    }

    assert {:error, _changeset} =
             struct(InspectionSchema)
             |> InspectionSchema.changeset(%{attrs | token: Ecto.UUID.generate()})
             |> Repo.insert()

    assert {:error, _changeset} =
             struct(InspectionEventSchema)
             |> InspectionEventSchema.changeset(%{media_file_id: file.id, token: token})
             |> Repo.insert()
  end

  test "schedules first inspection once and reuses it on an unchanged scan", %{scan: scan} do
    running = start(scan)
    save(running, [entry("a.mp4")])
    [file] = files(scan.library_id)
    assert %{state: :pending, observed_revision: 1, token: token} = inspection(file.id)
    assert [%{token: ^token, delivered_at: nil}] = events(file.id)

    save(running, [entry("a.mp4")])
    assert [event] = events(file.id)
    assert event.token == token
    assert {:ok, _} = EctoScanRepository.complete(scan.id, running.generation)

    unchanged = next_scan(scan.library_id)
    save(unchanged, [entry("a.mp4")])
    assert inspection(file.id).token == token
    assert length(events(file.id)) == 1
  end

  test "schedules an existing H2b file without technical state", %{scan: scan} do
    running = start(scan)
    save(running, [entry("a.mp4")])
    [file] = files(scan.library_id)
    Repo.delete_all(from event in InspectionEventSchema, where: event.media_file_id == ^file.id)
    Repo.delete!(inspection(file.id))
    assert {:ok, _} = EctoScanRepository.complete(scan.id, running.generation)

    unchanged = next_scan(scan.library_id)
    save(unchanged, [entry("a.mp4")])
    assert %{state: :pending, observed_revision: 1} = inspection(file.id)
    assert [_event] = events(file.id)
  end

  test "reschedules changed and restored files while keeping their IDs", %{scan: scan} do
    initial = start(scan)
    save(initial, [entry("a.mp4")])
    [original] = files(scan.library_id)
    old_token = inspection(original.id).token
    assert {:ok, _} = EctoScanRepository.complete(scan.id, initial.generation)

    changed = next_scan(scan.library_id)
    save(changed, [entry("a.mp4", 6)])
    assert inspection(original.id).observed_revision == 2
    refute inspection(original.id).token == old_token
    assert length(events(original.id)) == 2
    assert {:ok, _} = EctoScanRepository.complete(changed.id, changed.generation)

    absent = next_scan(scan.library_id)
    assert {:ok, _} = EctoScanRepository.complete(absent.id, absent.generation)
    assert [%{id: id, availability: :missing}] = files(scan.library_id)
    assert id == original.id

    restored = next_scan(scan.library_id)
    save(restored, [entry("a.mp4", 6)])
    assert inspection(original.id).observed_revision == 2
    assert length(events(original.id)) == 3
  end

  test "forced scan creates a new token without changing revision", %{scan: scan} do
    initial = start(scan)
    save(initial, [entry("a.mp4")])
    [file] = files(scan.library_id)
    old_token = inspection(file.id).token
    assert {:ok, _} = EctoScanRepository.complete(scan.id, initial.generation)

    assert {:ok, forced_scan} = EctoScanRepository.request(scan.library_id, true)
    forced = start(forced_scan)
    save(forced, [entry("a.mp4")])
    save(forced, [entry("a.mp4")])
    assert inspection(file.id).observed_revision == 1
    refute inspection(file.id).token == old_token
    assert length(events(file.id)) == 2
  end

  test "begins each invocation with a new generation and preserves the first start",
       %{scan: scan, library: library} do
    assert {:ok, first, returned_library} = EctoScanRepository.begin_attempt(scan.id, 1)
    assert returned_library.id == library.id
    assert returned_library.path == library.path
    assert first.state == :running
    assert first.attempt == 1
    assert first.started_at == first.attempt_started_at
    assert {:ok, _} = EctoScanRepository.save_batch(scan.id, first.generation, [entry("a.mp4")])
    assert :ok = EctoScanRepository.fail(scan.id, first.generation, :timeout, :retrying)

    assert {:ok, next, _} = EctoScanRepository.begin_attempt(scan.id, 2)
    assert next.generation != first.generation
    assert next.attempt == 2
    assert next.files_discovered == 0
    assert next.started_at == first.started_at
    assert DateTime.compare(next.attempt_started_at, first.attempt_started_at) == :gt
    assert next.failure_reason == nil
    assert next.finished_at == nil
    assert {:error, :not_found} = EctoScanRepository.begin_attempt(0, 1)
  end

  test "keeps identity and revision when unchanged and revises size or modification changes",
       %{scan: scan} do
    first = start(scan)
    original = entry("movie.mp4")
    save(first, [original])
    assert [file] = files(scan.library_id)
    assert {:ok, _} = EctoScanRepository.complete(scan.id, first.generation)

    next = next_scan(scan.library_id)
    save(next, [original])
    assert [unchanged] = files(scan.library_id)
    assert unchanged.id == file.id
    assert unchanged.revision == 1

    save(next, [entry("movie.mp4", 9)])
    assert [resized] = files(scan.library_id)
    assert resized.id == file.id
    assert resized.revision == 2
    assert resized.size_bytes == 9

    save(next, [entry("movie.mp4", 9, DateTime.add(@modified, 1))])
    assert [modified] = files(scan.library_id)
    assert modified.id == file.id
    assert modified.revision == 3
    assert DateTime.compare(modified.modified_at, DateTime.add(@modified, 1)) == :eq
    assert stored_scan(next.id).files_discovered == 1
  end

  test "marks renamed paths absent after success and restores their original ID when seen again",
       %{scan: scan} do
    first = start(scan)
    save(first, [entry("original.mp4")])
    assert [original] = files(scan.library_id)
    assert {:ok, _} = EctoScanRepository.complete(scan.id, first.generation)

    next = next_scan(scan.library_id)
    save(next, [entry("renamed.mp4")])
    assert {:ok, completed} = EctoScanRepository.complete(next.id, next.generation)
    assert completed.state == :completed
    assert completed.finished_at != nil
    assert completed.failure_reason == nil
    assert [missing, renamed] = files(scan.library_id)
    assert missing.id == original.id
    assert missing.availability == :missing
    assert renamed.id != original.id
    assert renamed.availability == :available

    third = next_scan(scan.library_id)
    save(third, [entry("original.mp4")])
    assert [restored, _] = files(scan.library_id)
    assert restored.id == original.id
    assert restored.availability == :available
    assert restored.revision == 1
  end

  test "preserves non-UTF8 paths and counts paths in batches of one hundred", %{scan: scan} do
    running = start(scan)
    raw_path = <<255, 47, 254, 46, 109, 107, 118>>
    entries = [entry(raw_path) | Enum.map(1..99, &entry("movie-#{&1}.mp4"))]

    assert {:ok, %{files_discovered: 100}} =
             EctoScanRepository.save_batch(scan.id, running.generation, entries)

    assert {:ok, %{files_discovered: 100}} =
             EctoScanRepository.save_batch(scan.id, running.generation, Enum.reverse(entries))

    assert Enum.find(files(scan.library_id), &(&1.relative_path == raw_path)).relative_path ==
             raw_path

    assert length(files(scan.library_id)) == 100
  end

  test "an empty successful traversal only marks its own library absent", %{scan: scan} do
    first = start(scan)
    save(first, [entry("movie.mp4")])
    assert {:ok, _} = EctoScanRepository.complete(scan.id, first.generation)
    other_library = library_fixture()
    other = next_scan(other_library.id)
    save(other, [entry("movie.mp4")])
    assert {:ok, _} = EctoScanRepository.complete(other.id, other.generation)
    assert [own] = files(scan.library_id)
    assert [independent] = files(other_library.id)
    assert own.id != independent.id

    empty = next_scan(scan.library_id)

    assert {:ok, %{files_discovered: 0}} =
             EctoScanRepository.save_batch(empty.id, empty.generation, [])

    assert {:ok, %{files_discovered: 0}} = EctoScanRepository.complete(empty.id, empty.generation)
    assert [%{id: id, availability: :missing}] = files(scan.library_id)
    assert id == own.id
    assert [%{availability: :available}] = files(other_library.id)
  end

  test "partial failure keeps confirmed observations and previously available unseen files",
       %{scan: scan} do
    first = start(scan)
    save(first, [entry("previous.mp4"), entry("observed.mp4")])
    assert {:ok, _} = EctoScanRepository.complete(scan.id, first.generation)
    previous_ids = Map.new(files(scan.library_id), &{&1.relative_path, &1.id})

    partial = next_scan(scan.library_id)
    save(partial, [entry("observed.mp4", 8), entry("new.mp4")])
    assert :ok = EctoScanRepository.fail(partial.id, partial.generation, :source_changed, :failed)
    failed = stored_scan(partial.id)
    assert failed.state == :failed
    assert failed.failure_reason == :source_changed
    assert failed.files_discovered == 2
    assert failed.finished_at != nil
    assert Enum.all?(files(scan.library_id), &(&1.availability == :available))
    observed = Enum.find(files(scan.library_id), &(&1.relative_path == "observed.mp4"))
    assert observed.id == previous_ids["observed.mp4"]
    assert observed.size_bytes == 8
    assert observed.revision == 2
    assert Enum.any?(files(scan.library_id), &(&1.relative_path == "new.mp4"))
    assert {:ok, :terminal} = EctoScanRepository.begin_attempt(partial.id, 3)
    assert stored_scan(partial.id) == failed
  end

  test "retry completion ignores earlier observations when deciding absences", %{scan: scan} do
    old = start(scan)
    save(old, [entry("old.mp4")])
    assert :ok = EctoScanRepository.fail(scan.id, old.generation, :entry_unreadable, :retrying)
    retrying = stored_scan(scan.id)
    assert retrying.finished_at == nil
    assert retrying.failure_reason == :entry_unreadable
    assert {:error, :stale_attempt} = EctoScanRepository.complete(scan.id, old.generation)

    assert {:error, :stale_attempt} =
             EctoScanRepository.save_batch(scan.id, old.generation, [entry("late.mp4")])

    assert {:ok, current, _} = EctoScanRepository.begin_attempt(scan.id, 2)
    save(current, [entry("current.mp4")])

    assert {:ok, %{files_discovered: 1}} =
             EctoScanRepository.complete(scan.id, current.generation)

    by_path = Map.new(files(scan.library_id), &{&1.relative_path, &1})
    assert by_path["old.mp4"].availability == :missing
    assert by_path["current.mp4"].availability == :available
  end

  test "stale finalization and failure cannot change current progress or availability",
       %{scan: scan} do
    old = start(scan)
    save(old, [entry("old.mp4")])
    assert {:ok, current, _} = EctoScanRepository.begin_attempt(scan.id, 1)
    save(current, [entry("current.mp4")])
    before = stored_scan(scan.id)
    inventory = files(scan.library_id)
    assert {:error, :stale_attempt} = EctoScanRepository.complete(scan.id, old.generation)

    assert {:error, :stale_attempt} =
             EctoScanRepository.fail(scan.id, old.generation, :timeout, :failed)

    assert stored_scan(scan.id) == before
    assert files(scan.library_id) == inventory
    assert {:ok, completed} = EctoScanRepository.complete(scan.id, current.generation)
    assert {:ok, :terminal} = EctoScanRepository.begin_attempt(scan.id, 2)
    assert {:error, :stale_attempt} = EctoScanRepository.complete(scan.id, current.generation)

    assert {:error, :stale_attempt} =
             EctoScanRepository.fail(scan.id, current.generation, :timeout, :retrying)

    assert stored_scan(scan.id) == completed
    assert {:error, :stale_attempt} = EctoScanRepository.save_batch(0, current.generation, [])
    assert {:error, :stale_attempt} = EctoScanRepository.complete(0, current.generation)

    assert {:error, :stale_attempt} =
             EctoScanRepository.fail(0, current.generation, :timeout, :failed)
  end

  @tag committed: true
  test "concurrent duplicate and distinct batches on independent connections preserve progress" do
    supervisor = start_supervised!(Task.Supervisor)
    parent = self()

    with_committed_scan(fn scan ->
      running = start(scan)

      tasks =
        for path <- ["same.mp4", "same.mp4", "other.mp4"] do
          Task.Supervisor.async_nolink(supervisor, fn ->
            Sandbox.unboxed_run(Repo, fn ->
              send(parent, {:ready, self()})

              receive do
                :go ->
                  EctoScanRepository.save_batch(scan.id, running.generation, [entry(path)])
              end
            end)
          end)
        end

      pids =
        for _ <- tasks do
          assert_receive {:ready, pid}, 1_000
          pid
        end

      Enum.each(pids, &send(&1, :go))

      for task <- tasks do
        assert {:ok, %{files_discovered: count}} = Task.await(task)
        assert count in [1, 2]
      end

      assert [first, second] = files(scan.library_id)
      assert Enum.all?([first, second], &(&1.revision == 1 and &1.availability == :available))
      assert stored_scan(scan.id).files_discovered == 2
    end)
  end

  @tag committed: true
  test "inspection cannot publish after a concurrent absence commits" do
    supervisor = start_supervised!(Task.Supervisor)
    parent = self()

    with_committed_scan(fn scan ->
      running = start(scan)
      save(running, [entry("film.mkv")])
      [file] = files(scan.library_id)
      token = inspection(file.id).token

      assert {:ok, _file, _library} =
               EctoInspectionRepository.begin_inspection(file.id, token, nil)

      {:ok, media} = TechnicalMedia.new(%{tracks: []})

      absent =
        Task.Supervisor.async_nolink(supervisor, fn ->
          Sandbox.unboxed_run(Repo, fn ->
            Repo.transaction(fn ->
              Repo.update_all(from(row in MediaFileSchema, where: row.id == ^file.id),
                set: [availability: :missing]
              )

              send(parent, {:absence_locked, self()})

              receive do
                :commit_absence -> :ok
              end
            end)
          end)
        end)

      assert_receive {:absence_locked, absent_pid}, 1_000

      completion =
        Task.Supervisor.async_nolink(supervisor, fn ->
          Sandbox.unboxed_run(Repo, fn ->
            send(parent, :completion_started)
            result = EctoInspectionRepository.complete_inspection(file.id, token, media)
            send(parent, {:completion_result, result})
            result
          end)
        end)

      assert_receive :completion_started, 1_000

      try do
        refute_receive {:completion_result, _}, 100
      after
        send(absent_pid, :commit_absence)
        assert {:ok, :ok} = Task.await(absent)
      end

      assert {:ok, :stale} = Task.await(completion)
      assert %{state: :running} = inspection(file.id)
    end)
  end

  @tag committed: true
  test "rolls back file upserts when PostgreSQL rejects the scan counter" do
    with_committed_scan(fn scan ->
      running = start(scan)
      save(running, [entry("existing.mp4")])
      before_scan = stored_scan(scan.id)
      before_files = files(scan.library_id)

      SQL.query!(Repo, """
      ALTER TABLE library_scans ADD CONSTRAINT inventory_test_reject_count
      CHECK (id <> #{scan.id} OR files_discovered <= 1) NOT VALID
      """)

      try do
        assert {:error, :unavailable} =
                 EctoScanRepository.save_batch(scan.id, running.generation, [
                   entry("existing.mp4", 50),
                   entry("new.mp4")
                 ])

        assert files(scan.library_id) == before_files
        assert stored_scan(scan.id) == before_scan
      after
        SQL.query!(
          Repo,
          "ALTER TABLE library_scans DROP CONSTRAINT inventory_test_reject_count"
        )
      end
    end)
  end

  @tag committed: true
  test "rolls back file, inspection and counter when outbox insertion fails" do
    with_committed_scan(fn scan ->
      running = start(scan)
      save(running, [entry("existing.mp4")])
      [existing] = files(scan.library_id)
      before_scan = stored_scan(scan.id)
      before_inspection = inspection(existing.id)
      before_events = events(existing.id)

      SQL.query!(Repo, """
      ALTER TABLE media_inspection_events ADD CONSTRAINT inventory_test_reject_event
      CHECK (media_file_id <> #{existing.id}) NOT VALID
      """)

      try do
        assert {:error, :unavailable} =
                 EctoScanRepository.save_batch(scan.id, running.generation, [
                   entry("existing.mp4", 50),
                   entry("new.mp4")
                 ])

        assert [file] = files(scan.library_id)
        assert file == existing
        assert inspection(existing.id) == before_inspection
        assert events(existing.id) == before_events
        assert stored_scan(scan.id) == before_scan
      after
        SQL.query!(
          Repo,
          "ALTER TABLE media_inspection_events DROP CONSTRAINT inventory_test_reject_event"
        )
      end
    end)
  end

  @tag committed: true
  test "rolls back absence changes when PostgreSQL rejects scan completion" do
    with_committed_scan(fn scan ->
      running = start(scan)
      save(running, [entry("existing.mp4")])
      assert {:ok, _} = EctoScanRepository.complete(scan.id, running.generation)
      current = next_scan(scan.library_id)
      before = stored_scan(current.id)

      SQL.query!(Repo, """
      ALTER TABLE library_scans ADD CONSTRAINT inventory_test_reject_completion
      CHECK (id <> #{current.id} OR state <> 'completed') NOT VALID
      """)

      try do
        assert {:error, :unavailable} =
                 EctoScanRepository.complete(current.id, current.generation)

        assert [%{availability: :available}] = files(scan.library_id)
        assert stored_scan(current.id) == before
      after
        SQL.query!(
          Repo,
          "ALTER TABLE library_scans DROP CONSTRAINT inventory_test_reject_completion"
        )
      end
    end)
  end

  test "music inventory schedules inspection without identification" do
    library = library_fixture()
    Repo.update!(Ecto.Changeset.change(library, content_type: :music))
    running = next_scan(library.id)
    save(running, [entry("song.mp3")])
    [file] = files(library.id)
    assert inspection(file.id).state == :pending
    assert length(events(file.id)) == 1
    assert identification_events(file.id) == []
    assert Repo.get_by(MovieIdentificationSchema, media_file_id: file.id) == nil
  end

  defp library_fixture do
    %LibrarySchema{}
    |> LibrarySchema.changeset(%{
      name: "Inventory",
      path: "/inventory-#{System.unique_integer([:positive])}"
    })
    |> Repo.insert!()
  end

  defp entry(path, size \\ 5, modified_at \\ @modified) do
    {:ok, entry} =
      NewMediaFile.new(%{relative_path: path, size_bytes: size, modified_at: modified_at})

    entry
  end

  defp start(scan) do
    assert {:ok, running, _} = EctoScanRepository.begin_attempt(scan.id, 1)
    running
  end

  defp next_scan(library_id) do
    {:ok, scan} = EctoScanRepository.request(library_id)
    start(scan)
  end

  defp save(scan, entries) do
    assert {:ok, _} = EctoScanRepository.save_batch(scan.id, scan.generation, entries)
  end

  defp files(library_id) do
    Repo.all(
      from file in MediaFileSchema, where: file.library_id == ^library_id, order_by: file.id
    )
    |> Enum.map(&MediaFileMapper.to_media_file/1)
  end

  defp stored_scan(id), do: Repo.get!(ScanSchema, id) |> ScanMapper.to_scan()

  defp inspection(file_id), do: Repo.get_by!(InspectionSchema, media_file_id: file_id)

  defp events(file_id) do
    Repo.all(
      from event in InspectionEventSchema,
        where: event.media_file_id == ^file_id,
        order_by: event.id
    )
  end

  defp identification_events(file_id) do
    Repo.all(
      from event in MovieIdentificationEventSchema,
        where: event.media_file_id == ^file_id,
        order_by: event.id
    )
  end

  defp with_committed_scan(callback) do
    with_committed_scans(1, fn [scan] -> callback.(scan) end)
  end

  defp with_committed_scans(count, callback) do
    Sandbox.unboxed_run(Repo, fn ->
      fixtures =
        for _ <- 1..count do
          library = library_fixture()
          {:ok, scan} = EctoScanRepository.request(library.id)
          {library, scan}
        end

      try do
        callback.(Enum.map(fixtures, fn {_library, scan} -> scan end))
      after
        Enum.each(fixtures, fn {library, _scan} ->
          job_ids =
            Repo.all(
              from row in ScanSchema, where: row.library_id == ^library.id, select: row.job_id
            )

          Repo.delete_all(from row in MediaFileSchema, where: row.library_id == ^library.id)
          Repo.delete_all(from row in ScanSchema, where: row.library_id == ^library.id)
          Repo.delete_all(from job in Oban.Job, where: job.id in ^job_ids)
          Repo.delete!(library)
        end)
      end
    end)
  end

  defp assert_committed_fixtures_removed(library_ids) do
    Sandbox.unboxed_run(Repo, fn ->
      query = from library in LibrarySchema, where: library.id in ^library_ids
      assert Repo.aggregate(query, :count, :id) == 0
    end)
  end
end
