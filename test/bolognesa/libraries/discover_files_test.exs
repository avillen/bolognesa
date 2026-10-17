defmodule Bolognesa.Libraries.DiscoverFilesTest do
  use Bolognesa.DataCase, async: false
  alias Bolognesa.Libraries.Application.UseCases.ReconcileScans
  alias Bolognesa.Libraries.Infrastructure.Services.LibraryStatusNotifications

  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.{MediaFileSchema, ScanSchema}
  alias Bolognesa.Libraries.Application.UseCases.DiscoverFiles
  alias Bolognesa.Libraries.Domain.ValueObjects.Files.NewMediaFile
  alias Bolognesa.Libraries.Infrastructure.Jobs.ScanWorker
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoScanRepository
  alias Bolognesa.Libraries.Support.{ControlledFileDiscovery, UnavailableScanRepository}
  alias Ecto.Adapters.SQL.Sandbox
  @moduletag capture_log: true
  require Logger

  setup do
    library =
      %LibrarySchema{}
      |> LibrarySchema.changeset(%{
        name: "Discovery",
        path: "/discovery-#{System.unique_integer([:positive])}"
      })
      |> Repo.insert!()

    {:ok, scan} = EctoScanRepository.request(library.id)
    supervisor = start_supervised!(Task.Supervisor)
    %{scan: scan, supervisor: supervisor}
  end

  test "completes only after a successful walk and completed replay has no effect", context do
    task = start_discovery(context)
    assert_receive {:discovery_request, %{content_type: :movie, path: path}}
    assert path == Repo.get!(LibrarySchema, context.scan.library_id).path
    send(task.pid, {:batch, [entry()]})
    assert_receive {:batch_result, _, :ok}
    assert Repo.get!(ScanSchema, context.scan.id).state == :running
    send(task.pid, {:finish, :ok})
    assert :ok = Task.await(task)
    {:ok, before} = EctoScanRepository.fetch_status(context.scan.library_id)
    assert before.latest_scan.state == :completed
    assert before.latest_scan.files_discovered == 1

    assert :ok =
             DiscoverFiles.call(
               context.scan.id,
               2,
               EctoScanRepository,
               ControlledFileDiscovery,
               LibraryStatusNotifications
             )

    assert {:ok, ^before} = EctoScanRepository.fetch_status(context.scan.library_id)
  end

  test "permanent disk failure preserves batches and permits explicit retry", context do
    task = start_discovery(context)
    send(task.pid, {:batch, [entry()]})
    assert_receive {:batch_result, _, :ok}
    send(task.pid, {:finish, {:error, :source_changed}})
    assert {:cancel, :source_changed} = Task.await(task)

    assert %{state: :failed, failure_reason: :source_changed} =
             Repo.get!(ScanSchema, context.scan.id)

    assert [%{availability: :available}] = Repo.all(MediaFileSchema)
    assert {:ok, _new_scan} = EctoScanRepository.request(context.scan.library_id)
  end

  test "persistence failure retries until the engine discards the last attempt", context do
    for {attempt, expected_state} <- [{1, :retrying}, {3, :retrying}] do
      task = start_discovery(context, attempt, UnavailableScanRepository)
      send(task.pid, {:batch, [entry()]})
      assert_receive {:batch_result, _, {:error, :unavailable}}
      assert {:error, :storage_unavailable} = Task.await(task)

      assert %{state: ^expected_state, failure_reason: :storage_unavailable} =
               Repo.get!(ScanSchema, context.scan.id)
    end

    Repo.get!(Oban.Job, context.scan.job_id)
    |> Ecto.Changeset.change(state: "discarded")
    |> Repo.update!()

    assert :ok =
             ReconcileScans.call(
               DateTime.utc_now(),
               EctoScanRepository,
               LibraryStatusNotifications
             )

    assert %{state: :failed, failure_reason: :storage_unavailable} =
             Repo.get!(ScanSchema, context.scan.id)

    assert {:ok, _} = EctoScanRepository.request(context.scan.library_id)
  end

  test "a stale execution finishes without mutating the current generation", context do
    task = start_discovery(context)
    {:ok, current, _} = EctoScanRepository.begin_attempt(context.scan.id, 2)
    send(task.pid, {:batch, [entry()]})
    assert_receive {:batch_result, _, {:error, :stale_attempt}}
    assert :ok = Task.await(task)

    assert {:ok, %{latest_scan: ^current}} =
             EctoScanRepository.fetch_status(context.scan.library_id)

    assert Repo.all(MediaFileSchema) == []
  end

  test "safe boundary strips external exceptions, SQL values, throws and exits", context do
    private = "/private/secret-family/movie.mkv"

    for command <- [
          {:raise, RuntimeError.exception(private)},
          {:raise, Postgrex.Error.exception(message: private)},
          {:throw, private},
          {:exit, private}
        ] do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          task = start_worker(context)
          send(task.pid, command)
          assert {:error, :unexpected_failure} = Task.await(task)
        end)

      refute log =~ private
    end
  end

  test "debug SQL logging does not expose private inventory path binds", context do
    level = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: level) end)
    private = "private-family-title.mkv"

    {:ok, entry} =
      NewMediaFile.new(%{
        relative_path: private,
        size_bytes: 5,
        modified_at: ~U[2026-10-03 00:00:00Z]
      })

    log =
      ExUnit.CaptureLog.capture_log([level: :debug], fn ->
        task = start_worker(context)
        send(task.pid, {:batch, [entry]})
        assert_receive {:batch_result, _, :ok}
        send(task.pid, {:finish, :ok})
        assert :ok = Task.await(task)
      end)

    refute log =~ private
  end

  test "real formatter exposes scan identifiers counters and measured duration", context do
    previous_level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous_level) end)
    formatter = Application.fetch_env!(:logger, :default_formatter)

    log =
      ExUnit.CaptureLog.capture_log(formatter ++ [level: :info], fn ->
        Logger.info("Scan formatter context", request_id: "scan-test-request")
        task = start_worker(context)
        send(task.pid, {:batch, [entry()]})
        assert_receive {:batch_result, _, :ok}
        send(task.pid, {:finish, :ok})
        assert :ok = Task.await(task)
      end)

    assert log =~ "request_id=scan-test-request"
    assert log =~ "Library scan completed"
    assert log =~ "library_id=#{context.scan.library_id}"
    assert log =~ "scan_id=#{context.scan.id}"
    assert log =~ "job_id=#{context.scan.job_id}"
    assert log =~ "attempt=1"
    assert log =~ "files_discovered=1"
    assert log =~ ~r/duration_ms=\d+/
    refute log =~ "movie.mp4"
  end

  defp start_discovery(context, attempt \\ 1, repository \\ EctoScanRepository) do
    start_task(context, fn ->
      DiscoverFiles.call(
        context.scan.id,
        attempt,
        repository,
        ControlledFileDiscovery,
        LibraryStatusNotifications
      )
    end)
  end

  defp start_worker(context) do
    job = %Oban.Job{id: context.scan.job_id, args: %{"scan_id" => context.scan.id}, attempt: 1}

    start_task(context, fn ->
      ScanWorker.perform(job, EctoScanRepository, ControlledFileDiscovery)
    end)
  end

  defp start_task(context, callback) do
    owner = self()

    task =
      Task.Supervisor.async_nolink(context.supervisor, fn ->
        ControlledFileDiscovery.configure(owner)
        callback.()
      end)

    Sandbox.allow(Repo, self(), task.pid)
    assert_receive {:walking, pid}, 1_000
    assert pid == task.pid
    task
  end

  defp entry do
    {:ok, entry} =
      NewMediaFile.new(%{
        relative_path: "movie.mp4",
        size_bytes: 5,
        modified_at: ~U[2026-10-03 00:00:00Z]
      })

    entry
  end
end
