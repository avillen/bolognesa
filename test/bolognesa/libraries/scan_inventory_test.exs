defmodule Bolognesa.Libraries.ScanInventoryTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Libraries.Domain.NewMediaFile
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoLibraryRepository.LibrarySchema
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository
  alias EctoScanRepository.{MediaFileMapper, MediaFileSchema, ScanMapper, ScanSchema}

  @modified ~U[2026-10-03 00:00:00Z]

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

    assert {:error, :stale_attempt} =
             EctoScanRepository.save_batch(scan.id, old.generation, [entry])

    assert {:ok, saved = %{files_discovered: 1}} =
             EctoScanRepository.save_batch(scan.id, current.generation, [entry, entry])

    assert DateTime.compare(saved.updated_at, current.updated_at) == :gt

    assert {:ok, %{files_discovered: 1}} =
             EctoScanRepository.save_batch(scan.id, current.generation, [entry])

    assert [file] = files(current.library_id)
    assert file.revision == 1
    assert file.last_seen_generation == current.generation
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
            Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
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
  test "rolls back file upserts when PostgreSQL rejects the scan counter" do
    with_committed_scan(fn scan ->
      running = start(scan)
      save(running, [entry("existing.mp4")])
      before_scan = stored_scan(scan.id)
      before_files = files(scan.library_id)

      Ecto.Adapters.SQL.query!(Repo, """
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
        Ecto.Adapters.SQL.query!(
          Repo,
          "ALTER TABLE library_scans DROP CONSTRAINT inventory_test_reject_count"
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

      Ecto.Adapters.SQL.query!(Repo, """
      ALTER TABLE library_scans ADD CONSTRAINT inventory_test_reject_completion
      CHECK (id <> #{current.id} OR state <> 'completed') NOT VALID
      """)

      try do
        assert {:error, :unavailable} =
                 EctoScanRepository.complete(current.id, current.generation)

        assert [%{availability: :available}] = files(scan.library_id)
        assert stored_scan(current.id) == before
      after
        Ecto.Adapters.SQL.query!(
          Repo,
          "ALTER TABLE library_scans DROP CONSTRAINT inventory_test_reject_completion"
        )
      end
    end)
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

  defp with_committed_scan(callback) do
    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      library = library_fixture()
      {:ok, scan} = EctoScanRepository.request(library.id)

      try do
        callback.(scan)
      after
        job_ids =
          Repo.all(
            from row in ScanSchema, where: row.library_id == ^library.id, select: row.job_id
          )

        Repo.delete_all(from row in MediaFileSchema, where: row.library_id == ^library.id)
        Repo.delete_all(from row in ScanSchema, where: row.library_id == ^library.id)
        Repo.delete_all(from job in Oban.Job, where: job.id in ^job_ids)
        Repo.delete!(library)
      end
    end)
  end
end
