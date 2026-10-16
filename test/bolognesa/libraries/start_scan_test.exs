defmodule Bolognesa.Libraries.StartScanTest do
  use Bolognesa.DataCase, async: false
  alias Bolognesa.Libraries.Application.UseCases.ReconcileScans
  alias Bolognesa.Libraries.Infrastructure.Services.LibraryStatusNotifications

  alias Bolognesa.Accounts.Domain.Entities.Actor
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.{MediaFileSchema, ScanSchema}
  alias Bolognesa.Libraries
  alias Bolognesa.Libraries.Application.UseCases.{GetInspectionCounts, GetScanStatus, StartScan}
  alias Bolognesa.Libraries.Domain.ReadModels.Scans.InspectionCounts
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoScanRepository
  alias Ecto.Adapters.SQL
  alias EctoScanRepository.MediaFileMapper
  alias SQL.Sandbox

  use Oban.Testing, repo: Bolognesa.Repo

  @admin %Actor{id: 1, name: "Ada", email: "ada@example.com", role: :admin}
  @member %Actor{id: 2, name: "Joe", email: "joe@example.com", role: :member}

  setup do
    root = Application.fetch_env!(:bolognesa, :library_roots) |> hd()
    path = Path.join(root, "scan-source-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)

    {:ok, library} =
      Libraries.create_library(@admin, %{name: "Movies", path: path, content_type: :movie})

    %{library: library, path: path}
  end

  test "persists a queued scan and rejects another active request", %{library: library} do
    :ok = Phoenix.PubSub.subscribe(Bolognesa.PubSub, "libraries:statuses")
    assert {:ok, scan} = Libraries.start_scan(@admin, library.id)
    library_id = library.id
    assert_receive {:library_status_changed, ^library_id}
    assert scan.library_id == library.id
    assert scan.state == :queued
    assert scan.attempt == 0
    assert scan.files_discovered == 0

    assert [%Oban.Job{args: %{"scan_id" => id}, id: job_id} = job] =
             all_enqueued(queue: "library_scans")

    assert id == scan.id
    assert job_id == scan.job_id
    assert job.max_attempts == 3
    assert job.worker == "Bolognesa.Libraries.Infrastructure.Jobs.ScanWorker"
    assert {:error, :scan_in_progress} = Libraries.start_scan(@admin, library.id)
    assert {:ok, status} = Libraries.get_scan_status(@admin, library.id)
    assert status.latest_scan == scan
    assert status.last_completed_at == nil
    refute_receive {:library_status_changed, _}
  end

  test "unavailable notifications do not change a committed scan request", %{library: library} do
    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:ok, scan} =
                 StartScan.call(
                   @admin,
                   library.id,
                   EctoScanRepository,
                   Bolognesa.Libraries.Support.UnavailableLibraryStatusNotifier
                 )

        assert scan.state == :queued
        assert Repo.get!(ScanSchema, scan.id).state == :queued

        assert_enqueued(
          worker: Bolognesa.Libraries.Infrastructure.Jobs.ScanWorker,
          args: %{scan_id: scan.id}
        )
      end)

    assert log =~ "Library status notification unavailable"
  end

  test "persists an authorized forced inspection request", %{library: library} do
    assert {:ok, scan} = Libraries.start_scan(@admin, library.id, force_inspection?: true)
    assert scan.force_inspection?
    assert Repo.get!(ScanSchema, scan.id).force_inspection

    assert {:error, :forbidden} =
             Libraries.start_scan(@member, library.id, force_inspection?: true)
  end

  test "reports no previous scan", %{library: library} do
    assert {:ok, status} = Libraries.get_scan_status(@admin, library.id)
    assert status.library_id == library.id
    assert status.latest_scan == nil
    assert status.last_completed_at == nil
  end

  test "authorizes technical counters and reports empty libraries", %{library: library} do
    assert {:ok, %{uninspected: 0, pending: 0, running: 0, succeeded: 0, failed: 0} = counts} =
             Libraries.get_inspection_counts(@admin, library.id)

    assert counts.__struct__ == InspectionCounts

    assert {:error, :forbidden} = Libraries.get_inspection_counts(@member, library.id)
    assert {:error, :forbidden} = Libraries.get_inspection_counts(nil, library.id)
    assert {:error, :not_found} = Libraries.get_inspection_counts(@admin, 0)
    assert {:error, :forbidden} = GetInspectionCounts.call(@member, 0, __MODULE__)
  end

  test "rejects absent libraries" do
    assert {:error, :not_found} = Libraries.start_scan(@admin, 0)
    assert {:error, :not_found} = Libraries.get_scan_status(@admin, 0)
  end

  test "requires an administrator for requests and status", %{library: library} do
    for actor <- [@member, nil] do
      assert {:error, :forbidden} = Libraries.start_scan(actor, library.id)
      assert {:error, :forbidden} = Libraries.get_scan_status(actor, library.id)
      assert {:error, :forbidden} = Libraries.start_scan(actor, 0)
      assert {:error, :forbidden} = Libraries.get_scan_status(actor, 0)
    end
  end

  test "authorizes before invoking the repository" do
    for actor <- [@member, nil] do
      assert {:error, :forbidden} =
               StartScan.call(actor, 0, __MODULE__, LibraryStatusNotifications)

      assert {:error, :forbidden} = GetScanStatus.call(actor, 0, __MODULE__)
    end
  end

  test "blocks requests while running or retrying", %{library: library} do
    {:ok, scan} = Libraries.start_scan(@admin, library.id)

    for state <- [:running, :retrying] do
      scan.id
      |> then(&Repo.get!(ScanSchema, &1))
      |> ScanSchema.changeset(%{state: state})
      |> Repo.update!()

      assert {:error, :scan_in_progress} = Libraries.start_scan(@admin, library.id)
    end

    assert Repo.aggregate(ScanSchema, :count) == 1
    assert length(all_enqueued(queue: "library_scans")) == 1
  end

  test "orders latest requests by timestamp then ID and retains the last completion",
       %{library: library} do
    time = DateTime.utc_now()
    first = request_terminal_scan(library.id, :completed, DateTime.add(time, -60))
    second = request_terminal_scan(library.id, :completed, time)
    third = request_terminal_scan(library.id, :failed, DateTime.add(time, 60))

    for scan <- [first, second, third] do
      scan |> ScanSchema.changeset(%{requested_at: time}) |> Repo.update!()
    end

    assert {:ok, status} = Libraries.get_scan_status(@admin, library.id)
    assert status.latest_scan.id == third.id
    assert status.latest_scan.state == :failed
    assert status.last_completed_at == time

    first |> ScanSchema.changeset(%{requested_at: DateTime.add(time, 120)}) |> Repo.update!()
    assert {:ok, status} = Libraries.get_scan_status(@admin, library.id)
    assert status.latest_scan.id == first.id
  end

  test "rolls back the scan when PostgreSQL rejects the job insertion", %{path: path} do
    with_committed_library(path, fn library ->
      SQL.query!(Repo, """
      ALTER TABLE oban_jobs ADD CONSTRAINT scan_test_reject_job
      CHECK (queue <> 'library_scans') NOT VALID
      """)

      try do
        assert {:error, :unavailable} = Libraries.start_scan(@admin, library.id)

        assert Repo.aggregate(
                 from(scan in ScanSchema, where: scan.library_id == ^library.id),
                 :count
               ) == 0

        assert Repo.aggregate(Oban.Job, :count) == 0
      after
        SQL.query!(
          Repo,
          "ALTER TABLE oban_jobs DROP CONSTRAINT scan_test_reject_job"
        )
      end
    end)
  end

  test "simultaneous requests persist one scan and one matching job", %{path: path} do
    supervisor = start_supervised!(Task.Supervisor)
    parent = self()

    with_committed_library(path, fn library ->
      tasks =
        for _ <- 1..2 do
          Task.Supervisor.async_nolink(supervisor, fn ->
            Sandbox.unboxed_run(Repo, fn ->
              send(parent, {:ready, self()})

              receive do
                :go -> Libraries.start_scan(@admin, library.id)
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
      results = Enum.map(tasks, &Task.await/1)
      assert [{:ok, scan}] = Enum.filter(results, &match?({:ok, _}, &1))
      assert Enum.count(results, &(&1 == {:error, :scan_in_progress})) == 1
      assert [stored] = Repo.all(from row in ScanSchema, where: row.library_id == ^library.id)
      assert stored.id == scan.id

      assert [%Oban.Job{id: job_id, args: %{"scan_id" => scan_id}}] =
               all_enqueued(queue: "library_scans")

      assert job_id == scan.job_id
      assert scan_id == scan.id
    end)
  end

  test "preserves non-UTF8 relative path bytes in storage and mapping", %{library: library} do
    attrs = %{
      library_id: library.id,
      relative_path: <<255, 47, 254, 46, 109, 107, 118>>,
      size_bytes: 0,
      modified_at: DateTime.utc_now(),
      last_seen_generation: Ecto.UUID.generate()
    }

    stored = %MediaFileSchema{} |> MediaFileSchema.changeset(attrs) |> Repo.insert!()
    file = stored.id |> then(&Repo.get!(MediaFileSchema, &1)) |> MediaFileMapper.to_media_file()
    assert file.relative_path == attrs.relative_path
    assert file.availability == :available
    assert file.revision == 1
    assert file.last_seen_generation == attrs.last_seen_generation
  end

  test "PostgreSQL rejects negative scan counters and invalid file measurements",
       %{library: library} do
    {:ok, scan} = Libraries.start_scan(@admin, library.id)

    attrs = %{
      library_id: library.id,
      relative_path: "movie.mkv",
      size_bytes: 0,
      modified_at: DateTime.utc_now(),
      last_seen_generation: Ecto.UUID.generate()
    }

    file = %MediaFileSchema{} |> MediaFileSchema.changeset(attrs) |> Repo.insert!()

    for {query, id} <- [
          {"UPDATE library_scans SET attempt = -1 WHERE id = $1", scan.id},
          {"UPDATE library_scans SET files_discovered = -1 WHERE id = $1", scan.id},
          {"UPDATE media_files SET size_bytes = -1 WHERE id = $1", file.id},
          {"UPDATE media_files SET revision = 0 WHERE id = $1", file.id}
        ] do
      assert_raise Postgrex.Error, fn ->
        SQL.query!(Repo, query, [id], mode: :savepoint)
      end
    end

    assert Repo.get!(ScanSchema, scan.id).files_discovered == 0
    assert Repo.get!(MediaFileSchema, file.id).revision == 1
  end

  test "job reconciliation is a no-op without active scans" do
    assert :ok =
             ReconcileScans.call(
               DateTime.utc_now(),
               EctoScanRepository,
               LibraryStatusNotifications
             )
  end

  defp request_terminal_scan(library_id, state, finished_at) do
    {:ok, scan} = Libraries.start_scan(@admin, library_id)

    scan.id
    |> then(&Repo.get!(ScanSchema, &1))
    |> ScanSchema.changeset(%{state: state, finished_at: finished_at})
    |> Repo.update!()
  end

  defp with_committed_library(path, callback) do
    Sandbox.unboxed_run(Repo, fn ->
      committed_path = path <> "-committed"
      File.mkdir_p!(committed_path)

      {:ok, library} =
        Libraries.create_library(@admin, %{
          name: "Concurrent",
          path: committed_path,
          content_type: :movie
        })

      try do
        callback.(library)
      after
        job_ids =
          Repo.all(
            from scan in ScanSchema,
              where: scan.library_id == ^library.id,
              select: scan.job_id
          )

        Repo.delete_all(from job in Oban.Job, where: job.id in ^job_ids)
        Repo.delete_all(from scan in ScanSchema, where: scan.library_id == ^library.id)
        Repo.delete_all(from row in LibrarySchema, where: row.id == ^library.id)
        File.rm_rf!(committed_path)
      end
    end)
  end
end
