defmodule Bolognesa.Libraries.ScanRecoveryTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Libraries.Domain.ReadModels.ReconciliationResult

  alias Bolognesa.Libraries.Application.UseCases.ReconcileScans
  alias Bolognesa.Libraries.Infrastructure.Services.LibraryStatusNotifications

  alias Bolognesa.Libraries.Application.UseCases.DiscoverFiles
  alias Bolognesa.Libraries.Domain.ValueObjects.Files.NewMediaFile
  alias Bolognesa.Libraries.Infrastructure.Jobs.{ScanPolicy, ScanReconciler, ScanWorker}
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoScanRepository

  alias Bolognesa.Libraries.Support.{
    BlockingScanWorker,
    ControlledFileDiscovery,
    ControlledScanRepository
  }

  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.{MediaFileSchema, ScanSchema}

  setup do
    library =
      %LibrarySchema{}
      |> LibrarySchema.changeset(%{
        name: "Recovery",
        path: "/recovery-#{System.unique_integer([:positive])}"
      })
      |> Repo.insert!()

    {:ok, scan} = EctoScanRepository.request(library.id)
    %{scan: scan}
  end

  test "recovery processes at most 100 scans and continues on the next pass", %{scan: scan} do
    scans = [scan | Enum.map(1..100, &orphan_scan/1)]
    Enum.each(scans, &Repo.delete!(Repo.get!(Oban.Job, &1.job_id)))

    first = EctoScanRepository.reconcile_jobs(DateTime.utc_now())
    assert first.error == nil
    assert length(first.changed_library_ids) == 100

    assert Repo.aggregate(Ecto.Query.from(s in ScanSchema, where: s.state == :queued), :count) ==
             1

    second = EctoScanRepository.reconcile_jobs(DateTime.utc_now())
    assert second.error == nil
    assert length(second.changed_library_ids) == 1

    assert Repo.aggregate(Ecto.Query.from(s in ScanSchema, where: s.state == :queued), :count) ==
             0
  end

  test "scans with remaining budget or awaiting retry do not consume the recovery batch" do
    now = DateTime.utc_now()

    for index <- 1..100 do
      scan = orphan_scan(index)
      {:ok, current, _} = EctoScanRepository.begin_attempt(scan.id, 1)

      if rem(index, 2) == 0 do
        :ok =
          EctoScanRepository.fail(scan.id, current.generation, :storage_unavailable, :retrying)

        job_state(scan, "retryable")
      else
        job_state(scan, "completed")
      end
    end

    orphan = orphan_scan(101)
    Repo.delete!(Repo.get!(Oban.Job, orphan.job_id))
    result = EctoScanRepository.reconcile_jobs(DateTime.add(now, 1))
    assert result.error == nil
    assert result.changed_library_ids == [orphan.library_id]
  end

  test "running generation gets its full budget despite an old invocation's terminal or retryable result",
       %{scan: scan} do
    for state <- ["completed", "cancelled", "discarded", "retryable"] do
      {:ok, current, _} = EctoScanRepository.begin_attempt(scan.id, 2)
      job_state(scan, state)

      assert :ok =
               ReconcileScans.call(
                 DateTime.add(current.attempt_started_at, 599),
                 EctoScanRepository,
                 LibraryStatusNotifications
               )

      assert {:ok, %{latest_scan: ^current}} = EctoScanRepository.fetch_status(scan.library_id)
    end
  end

  for {job_state, domain_state, reason} <- [
        {"retryable", :retrying, :unexpected_failure},
        {"discarded", :failed, :attempts_exhausted},
        {"cancelled", :failed, :unexpected_failure},
        {"completed", :failed, :unexpected_failure}
      ] do
    test "expired running generation reconciles #{job_state} safely", %{scan: scan} do
      {:ok, current, _} = EctoScanRepository.begin_attempt(scan.id, 3)
      job_state(scan, unquote(job_state))
      now = DateTime.add(current.attempt_started_at, 600)
      :ok = Phoenix.PubSub.subscribe(Bolognesa.PubSub, "libraries:statuses")
      assert :ok = ReconcileScans.call(now, EctoScanRepository, LibraryStatusNotifications)
      library_id = scan.library_id
      assert_receive {:library_status_changed, ^library_id}

      assert %{state: unquote(domain_state), failure_reason: unquote(reason)} =
               Repo.get!(ScanSchema, scan.id)

      assert {:error, :stale_attempt} = EctoScanRepository.complete(scan.id, current.generation)
      assert :ok = ReconcileScans.call(now, EctoScanRepository, LibraryStatusNotifications)
      refute_receive {:library_status_changed, _}
    end
  end

  test "does not rescue executing jobs or overwrite a completed domain result", %{scan: scan} do
    {:ok, current, _} = EctoScanRepository.begin_attempt(scan.id, 1)
    job_state(scan, "executing")
    now = DateTime.add(current.attempt_started_at, 2_000)
    assert :ok = ReconcileScans.call(now, EctoScanRepository, LibraryStatusNotifications)
    assert {:ok, %{latest_scan: ^current}} = EctoScanRepository.fetch_status(scan.library_id)
    {:ok, completed} = EctoScanRepository.complete(scan.id, current.generation)
    job_state(scan, "discarded")
    assert :ok = ReconcileScans.call(now, EctoScanRepository, LibraryStatusNotifications)
    assert {:ok, %{latest_scan: ^completed}} = EctoScanRepository.fetch_status(scan.library_id)
  end

  test "orphan running scan waits for budget then fails and queued orphan fails immediately", %{
    scan: scan
  } do
    {:ok, current, _} = EctoScanRepository.begin_attempt(scan.id, 1)
    Repo.delete!(Repo.get!(Oban.Job, scan.job_id))

    assert :ok =
             ReconcileScans.call(
               current.attempt_started_at,
               EctoScanRepository,
               LibraryStatusNotifications
             )

    assert Repo.get!(ScanSchema, scan.id).state == :running

    assert :ok =
             ReconcileScans.call(
               DateTime.add(current.attempt_started_at, 600),
               EctoScanRepository,
               LibraryStatusNotifications
             )

    assert %{state: :failed, failure_reason: :unexpected_failure} = Repo.get!(ScanSchema, scan.id)
    {:ok, queued} = EctoScanRepository.request(scan.library_id)
    Repo.delete!(Repo.get!(Oban.Job, queued.job_id))

    assert :ok =
             ReconcileScans.call(
               DateTime.utc_now(),
               EctoScanRepository,
               LibraryStatusNotifications
             )

    assert Repo.get!(ScanSchema, queued.id).state == :failed
  end

  test "queued and retrying states reconcile terminal outcomes without a deadline", %{scan: scan} do
    job_state(scan, "discarded")

    assert :ok =
             ReconcileScans.call(
               DateTime.utc_now(),
               EctoScanRepository,
               LibraryStatusNotifications
             )

    assert %{state: :failed, failure_reason: :attempts_exhausted} = Repo.get!(ScanSchema, scan.id)
    {:ok, next} = EctoScanRepository.request(scan.library_id)
    {:ok, current, _} = EctoScanRepository.begin_attempt(next.id, 3)
    :ok = EctoScanRepository.fail(next.id, current.generation, :storage_unavailable, :retrying)
    job_state(next, "discarded")

    assert :ok =
             ReconcileScans.call(
               current.attempt_started_at,
               EctoScanRepository,
               LibraryStatusNotifications
             )

    assert %{state: :failed, failure_reason: :storage_unavailable} =
             Repo.get!(ScanSchema, next.id)
  end

  test "policy agrees with production configuration and worker options", %{scan: scan} do
    config = Config.Reader.read!("config/config.exs", env: :prod, target: :host)
    oban = config[:bolognesa][Oban]

    assert oban[:queues] == [
             library_scans: 1,
             media_inspections: 1,
             identifications: 1,
             music_imports: 1
           ]

    assert oban[:plugins] == [
             {Oban.Plugins.Lifeline,
              rescue_after: ScanPolicy.rescue_after_ms(),
              interval: ScanPolicy.reconcile_interval_ms()}
           ]

    assert ScanWorker.timeout(%Oban.Job{}) == 600_000
    assert ScanPolicy.timeout_ms() < ScanPolicy.rescue_after_ms()
    assert ScanPolicy.batch_size() == 100
    assert Repo.get!(Oban.Job, scan.job_id).max_attempts == ScanPolicy.max_attempts()
    assert ScanWorker.new(%{scan_id: scan.id}).changes.max_attempts == ScanPolicy.max_attempts()
  end

  test "Lifeline rescues interrupted execution after a confirmed batch and a new generation repeats safely",
       %{scan: scan} do
    owner = self()
    supervisor = start_supervised!(Task.Supervisor)

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        ControlledFileDiscovery.configure(owner)

        DiscoverFiles.call(
          scan.id,
          1,
          EctoScanRepository,
          ControlledFileDiscovery,
          LibraryStatusNotifications
        )
      end)

    assert_receive {:walking, pid}
    assert pid == task.pid
    send(pid, {:batch, [entry()]})
    assert_receive {:batch_result, ^pid, :ok}
    old = Repo.get!(ScanSchema, scan.id)
    [before] = Repo.all(MediaFileSchema)
    monitor = Process.monitor(pid)
    :ok = Task.Supervisor.terminate_child(supervisor, pid)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :shutdown}

    prepare_job(scan, "normal",
      state: "executing",
      attempt: 1,
      attempted_at: DateTime.add(DateTime.utc_now(), -901)
    )

    start_engine(lifeline: true)

    assert_receive {:engine_event, [:oban, :plugin, :stop], %{rescued_jobs: [%{id: rescued_id}]}},
                   2_000

    assert rescued_id == scan.job_id
    Oban.resume_queue(:ScanRecoveryOban, queue: :library_scans)
    assert_receive {:engine_started, id, worker, 2}, 2_000
    assert id == scan.job_id
    assert_receive {:walking, ^worker}
    assert Repo.get!(ScanSchema, scan.id).generation != old.generation
    send(worker, {:batch, [entry()]})
    assert_receive {:batch_result, ^worker, :ok}
    send(worker, {:finish, :ok})
    assert_job_event(scan.job_id, :stop)
    assert Repo.get!(Oban.Job, scan.job_id).state == "completed"
    assert Repo.get!(ScanSchema, scan.id).state == :completed
    assert [%{id: file_id, revision: 1}] = Repo.all(MediaFileSchema)
    assert file_id == before.id
  end

  test "real engine discards exhausted persistence failures and reconciliation frees the library",
       %{scan: scan} do
    prepare_job(scan, "storage", attempt: 2)
    start_engine()
    Oban.resume_queue(:ScanRecoveryOban, queue: :library_scans)
    assert_receive {:engine_started, _, worker, 3}, 2_000
    assert_receive {:walking, ^worker}

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        send(worker, {:batch, [entry()]})
        assert_receive {:batch_result, ^worker, {:error, :unavailable}}
        assert_job_event(scan.job_id, :exception)
      end)

    assert log =~ "Library scan execution failed"
    assert log =~ "reason=storage_unavailable"
    assert log =~ "library_id=#{scan.library_id}"
    assert Repo.get!(Oban.Job, scan.job_id).state == "discarded"
    assert Repo.get!(ScanSchema, scan.id).state == :retrying

    assert :ok =
             ReconcileScans.call(
               DateTime.utc_now(),
               EctoScanRepository,
               LibraryStatusNotifications
             )

    assert %{state: :failed, failure_reason: :storage_unavailable} =
             Repo.get!(ScanSchema, scan.id)

    stop_supervised!(:ScanRecoveryOban)
    assert {:ok, _} = EctoScanRepository.request(scan.library_id)
  end

  test "Lifeline discards abandoned execution at its last attempt", %{scan: scan} do
    {:ok, current, _} = EctoScanRepository.begin_attempt(scan.id, 3)

    prepare_job(scan, "normal",
      state: "executing",
      attempt: 3,
      attempted_at: DateTime.add(DateTime.utc_now(), -901)
    )

    start_engine(lifeline: true)
    assert_receive {:engine_event, [:oban, :plugin, :stop], %{discarded_jobs: [%{id: id}]}}, 2_000
    assert id == scan.job_id

    assert :ok =
             ReconcileScans.call(
               DateTime.add(current.attempt_started_at, 600),
               EctoScanRepository,
               LibraryStatusNotifications
             )

    assert %{state: :failed, failure_reason: :attempts_exhausted} = Repo.get!(ScanSchema, scan.id)
  end

  test "actual short worker timeout is persisted by Oban and reconciled after the generation budget",
       %{scan: scan} do
    prepare_job(scan, "timeout", attempt: 2)
    start_engine()
    Oban.resume_queue(:ScanRecoveryOban, queue: :library_scans)
    assert_receive {:engine_started, _, worker, 3}, 2_000
    assert_receive {:walking, ^worker}
    monitor = Process.monitor(worker)
    assert_receive {:DOWN, ^monitor, :process, ^worker, %Oban.TimeoutError{}}, 2_000
    assert_job_event(scan.job_id, :exception)
    assert Repo.get!(Oban.Job, scan.job_id).state == "discarded"
    current = Repo.get!(ScanSchema, scan.id)

    assert :ok =
             ReconcileScans.call(
               DateTime.add(current.attempt_started_at, 600),
               EctoScanRepository,
               LibraryStatusNotifications
             )

    assert Repo.get!(ScanSchema, scan.id).state == :failed
    assert ScanWorker.timeout(%Oban.Job{}) == 600_000
  end

  test "single queue slot keeps the second job waiting until the first finishes", %{scan: scan} do
    library =
      %LibrarySchema{}
      |> LibrarySchema.changeset(%{name: "Second", path: "/second-recovery"})
      |> Repo.insert!()

    {:ok, second} = EctoScanRepository.request(library.id)
    prepare_job(scan, "normal")
    prepare_job(second, "normal")
    start_engine()
    Oban.resume_queue(:ScanRecoveryOban, queue: :library_scans)
    assert_receive {:engine_started, first_id, worker, 1}, 2_000
    assert first_id == scan.job_id
    assert_receive {:walking, ^worker}
    assert Repo.get!(Oban.Job, second.job_id).state == "available"
    refute_receive {:engine_started, _, _, _}, 50
    send(worker, {:finish, :ok})
    assert_job_event(scan.job_id, :stop)
    assert_receive {:engine_started, second_id, second_worker, 1}, 2_000
    assert second_id == second.job_id
    assert_receive {:walking, ^second_worker}
    send(second_worker, {:finish, :ok})
    assert_job_event(second.job_id, :stop)
  end

  test "private exceptions and SQL exceptions never enter logs or persisted Oban errors", %{
    scan: scan
  } do
    private = "/private/test-sensitive-title.mkv"
    prepare_job(scan, "normal", attempt: 2)
    start_engine()
    level = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: level) end)

    log =
      ExUnit.CaptureLog.capture_log([level: :debug], fn ->
        Oban.resume_queue(:ScanRecoveryOban, queue: :library_scans)
        assert_receive {:engine_started, _, worker, 3}, 2_000
        assert_receive {:walking, ^worker}
        send(worker, {:raise, Postgrex.Error.exception(message: private)})
        assert_job_event(scan.job_id, :exception)
      end)

    Logger.configure(level: level)
    refute log =~ private
    job = Repo.get!(Oban.Job, scan.job_id)
    assert job.state == "discarded"
    assert length(job.errors) == 1
    refute inspect(job.errors) =~ private
    assert inspect(job.errors) =~ "unexpected_failure"
  end

  test "reconciler runs at startup and schedules the next pass only after the previous returns" do
    Process.register(self(), :scan_reconciliation_owner)

    pid =
      start_supervised!(
        {ScanReconciler,
         repository: ControlledScanRepository, name: :controlled_reconciler, interval_ms: 10}
      )

    assert_receive {:reconciliation, ^pid, %DateTime{}}
    refute_receive {:reconciliation, ^pid, _}, 30
    send(pid, {:reconciled, %ReconciliationResult{}})
    assert_receive {:reconciliation, ^pid, %DateTime{}}, 1_000

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        send(pid, {:reconciled, %ReconciliationResult{error: :unavailable}})
        assert_receive {:reconciliation, ^pid, %DateTime{}}, 1_000
      end)

    assert log =~ "Library scan reconciliation unavailable"
    send(pid, {:reconciled, %ReconciliationResult{}})
  end

  defp orphan_scan(index) do
    library =
      %LibrarySchema{}
      |> LibrarySchema.changeset(%{name: "Recovery #{index}", path: "/bounded-recovery-#{index}"})
      |> Repo.insert!()

    {:ok, scan} = EctoScanRepository.request(library.id)
    scan
  end

  defp prepare_job(scan, mode, attrs \\ []) do
    args = %{
      "scan_id" => scan.id,
      "owner" => self() |> :erlang.pid_to_list() |> List.to_string(),
      "mode" => mode
    }

    Repo.get!(Oban.Job, scan.job_id)
    |> Ecto.Changeset.change(
      Keyword.merge([worker: Oban.Worker.to_string(BlockingScanWorker), args: args], attrs)
    )
    |> Repo.update!()
  end

  defp start_engine(opts \\ []) do
    name = :ScanRecoveryOban
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach_many(
        handler,
        [[:oban, :job, :stop], [:oban, :job, :exception], [:oban, :plugin, :stop]],
        &BlockingScanWorker.telemetry/4,
        {self(), name}
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    plugins =
      if opts[:lifeline],
        do: [{Oban.Plugins.Lifeline, interval: 20, rescue_after: ScanPolicy.rescue_after_ms()}],
        else: false

    start_supervised!(
      {Oban,
       name: name,
       repo: Repo,
       testing: :disabled,
       queues: [library_scans: [limit: 1, paused: true]],
       plugins: plugins,
       peer: Oban.Peers.Isolated,
       notifier: Oban.Notifiers.Isolated,
       stage_interval: 20,
       shutdown_grace_period: 10}
    )
  end

  defp assert_job_event(id, event) do
    assert_receive {:engine_event, [:oban, :job, ^event], %{job: %{id: ^id}}}, 2_000
  end

  defp entry do
    {:ok, entry} =
      NewMediaFile.new(%{
        relative_path: "movie.mkv",
        size_bytes: 5,
        modified_at: ~U[2026-10-03 00:00:00Z]
      })

    entry
  end

  defp job_state(scan, state) do
    Repo.get!(Oban.Job, scan.job_id) |> Ecto.Changeset.change(state: state) |> Repo.update!()
  end
end
