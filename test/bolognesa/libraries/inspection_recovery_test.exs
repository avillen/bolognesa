defmodule Bolognesa.Libraries.InspectionRecoveryTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Libraries.Domain.NewMediaFile

  alias Bolognesa.Libraries.Infrastructure.Jobs.{
    InspectionPolicy,
    InspectionReconciler,
    InspectionWorker
  }

  alias Bolognesa.Persistence.LibrarySchema
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoInspectionRepository
  alias Bolognesa.Persistence.InspectionSchema
  alias Bolognesa.Libraries.Infrastructure.Persistence.{EctoOutboxRepository, EctoScanRepository}
  alias Bolognesa.Libraries.Support.{BlockingMediaProbe, RaisingMediaProbe, SuccessfulMediaProbe}

  setup do
    library =
      %LibrarySchema{}
      |> LibrarySchema.changeset(%{
        name: "Recovery",
        path: "/recovery-#{System.unique_integer([:positive])}"
      })
      |> Repo.insert!()

    {:ok, scan} = EctoScanRepository.request(library.id)
    {:ok, running, _} = EctoScanRepository.begin_attempt(scan.id, 1)

    {:ok, entry} =
      NewMediaFile.new(%{
        relative_path: "film.mkv",
        size_bytes: 5,
        modified_at: ~U[2026-10-03 00:00:00Z]
      })

    {:ok, _} = EctoScanRepository.save_batch(scan.id, running.generation, [entry])
    assert {:ok, 1} = EctoOutboxRepository.dispatch_batch(25)
    inspection = Repo.one!(InspectionSchema)
    %{inspection: inspection}
  end

  test "worker stores a result and a duplicate job stays harmless", %{inspection: inspection} do
    job = %Oban.Job{
      id: inspection.job_id,
      attempt: 1,
      args: %{"media_file_id" => inspection.media_file_id, "token" => inspection.token}
    }

    assert :ok = InspectionWorker.perform(job, EctoInspectionRepository, SuccessfulMediaProbe)
    assert :ok = InspectionWorker.perform(job, EctoInspectionRepository, SuccessfulMediaProbe)
    assert Repo.get!(InspectionSchema, inspection.id).state == :succeeded
    assert InspectionWorker.timeout(job) > 30_000
  end

  test "reconciles a completed job with no domain result", %{inspection: inspection} do
    Repo.get!(Oban.Job, inspection.job_id)
    |> Ecto.Changeset.change(state: "completed")
    |> Repo.update!()

    assert :ok = EctoInspectionRepository.reconcile_jobs(DateTime.utc_now())

    assert %{state: :failed, failure_reason: :unexpected_failure} =
             Repo.get!(InspectionSchema, inspection.id)
  end

  test "reconciles an exhausted job and leaves success intact", %{inspection: inspection} do
    Repo.get!(Oban.Job, inspection.job_id)
    |> Ecto.Changeset.change(state: "discarded")
    |> Repo.update!()

    pid =
      start_supervised!(
        {InspectionReconciler, name: :TestInspectionReconciler, interval_ms: 60_000}
      )

    _state = :sys.get_state(pid)

    assert %{state: :failed, failure_reason: :attempts_exhausted} =
             Repo.get!(InspectionSchema, inspection.id)

    assert InspectionPolicy.max_attempts() == 3
  end

  test "reconciles a lost job", %{inspection: inspection} do
    Repo.delete!(Repo.get!(Oban.Job, inspection.job_id))
    assert :ok = EctoInspectionRepository.reconcile_jobs(DateTime.utc_now())

    assert %{state: :failed, failure_reason: :unexpected_failure} =
             Repo.get!(InspectionSchema, inspection.id)
  end

  test "a running inspection beyond its budget becomes a visible timeout", %{
    inspection: inspection
  } do
    old =
      DateTime.add(DateTime.utc_now(), -InspectionPolicy.rescue_after_ms() - 1_000, :millisecond)

    Repo.get!(Oban.Job, inspection.job_id)
    |> Ecto.Changeset.change(state: "executing", attempted_at: old)
    |> Repo.update!()

    Repo.get!(InspectionSchema, inspection.id)
    |> Ecto.Changeset.change(state: :running, started_at: old)
    |> Repo.update!()

    assert :ok = EctoInspectionRepository.reconcile_jobs(DateTime.utc_now())

    assert %{state: :failed, failure_reason: :timeout} =
             Repo.get!(InspectionSchema, inspection.id)
  end

  test "a scheduled retry remains eligible and resets its attempt clock", %{
    inspection: inspection
  } do
    old =
      DateTime.add(DateTime.utc_now(), -InspectionPolicy.rescue_after_ms() - 1_000, :millisecond)

    Repo.get!(Oban.Job, inspection.job_id)
    |> Ecto.Changeset.change(
      state: "retryable",
      attempted_at: old,
      scheduled_at: DateTime.add(DateTime.utc_now(), 30)
    )
    |> Repo.update!()

    Repo.get!(InspectionSchema, inspection.id)
    |> Ecto.Changeset.change(state: :running, started_at: old)
    |> Repo.update!()

    assert :ok = EctoInspectionRepository.reconcile_jobs(DateTime.utc_now())
    assert %{state: :pending, failure_reason: nil} = Repo.get!(InspectionSchema, inspection.id)

    assert {:ok, _file, _library} =
             EctoInspectionRepository.begin_inspection(
               inspection.media_file_id,
               inspection.token,
               inspection.job_id
             )

    assert DateTime.compare(Repo.get!(InspectionSchema, inspection.id).started_at, old) == :gt
  end

  test "a recent Oban attempt is not failed because a previous attempt was old", %{
    inspection: inspection
  } do
    old =
      DateTime.add(DateTime.utc_now(), -InspectionPolicy.rescue_after_ms() - 1_000, :millisecond)

    Repo.get!(Oban.Job, inspection.job_id)
    |> Ecto.Changeset.change(state: "executing", attempted_at: DateTime.utc_now())
    |> Repo.update!()

    Repo.get!(InspectionSchema, inspection.id)
    |> Ecto.Changeset.change(state: :running, started_at: old)
    |> Repo.update!()

    assert :ok = EctoInspectionRepository.reconcile_jobs(DateTime.utc_now())
    assert Repo.get!(InspectionSchema, inspection.id).state == :running
  end

  test "worker keeps private probe exceptions out of logs and Oban errors", %{
    inspection: inspection
  } do
    job = %Oban.Job{
      id: inspection.job_id,
      attempt: 1,
      args: %{"media_file_id" => inspection.media_file_id, "token" => inspection.token}
    }

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, :unexpected_failure} =
                 InspectionWorker.perform(job, EctoInspectionRepository, RaisingMediaProbe)
      end)

    refute log =~ "/media/film.mkv"
    assert log =~ "unexpected_failure"
  end

  test "the real queue runs one inspection at a time", %{inspection: inspection} do
    parent = self()
    Process.register(parent, :inspection_probe_owner)
    previous = Application.get_env(:bolognesa, :media_probe_adapter)
    Application.put_env(:bolognesa, :media_probe_adapter, BlockingMediaProbe)
    on_exit(fn -> Application.put_env(:bolognesa, :media_probe_adapter, previous) end)

    file = Repo.get!(Bolognesa.Persistence.MediaFileSchema, inspection.media_file_id)
    scan = Repo.get_by!(Bolognesa.Persistence.ScanSchema, library_id: file.library_id)

    {:ok, entry} =
      NewMediaFile.new(%{
        relative_path: "second.mkv",
        size_bytes: 5,
        modified_at: ~U[2026-10-03 00:00:00Z]
      })

    assert {:ok, _} = EctoScanRepository.save_batch(scan.id, scan.generation, [entry])
    assert {:ok, 1} = EctoOutboxRepository.dispatch_batch(25)

    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:oban, :job, :stop],
        fn _event, _measurements, metadata, _config ->
          send(parent, {:inspection_job_stopped, metadata.job.id})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    start_supervised!(
      {Oban,
       name: :InspectionRecoveryOban,
       repo: Repo,
       testing: :disabled,
       queues: [media_inspections: [limit: 1, paused: true]],
       plugins: false,
       peer: Oban.Peers.Isolated,
       notifier: Oban.Notifiers.Isolated,
       stage_interval: 20}
    )

    Oban.resume_queue(:InspectionRecoveryOban, queue: :media_inspections)
    assert_receive {:probe_started, first_pid}, 2_000
    refute_receive {:probe_started, _}, 100
    send(first_pid, :probe_continue)
    assert_receive {:inspection_job_stopped, _}, 2_000
    assert_receive {:probe_started, second_pid}, 2_000
    send(second_pid, :probe_continue)
    assert_receive {:inspection_job_stopped, _}, 2_000

    assert Repo.aggregate(
             from(job in Oban.Job,
               where: job.queue == "media_inspections" and job.state == "completed"
             ),
             :count
           ) == 2
  end
end
