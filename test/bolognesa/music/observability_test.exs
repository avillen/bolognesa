defmodule Bolognesa.Music.ObservabilityTest do
  use Bolognesa.DataCase, async: true
  import Bolognesa.MusicFixtures

  alias Bolognesa.Infrastructure.Persistence.{MediaFileSchema, MusicImportSchema}
  alias Bolognesa.Music
  alias Bolognesa.Music.Application.UseCases.{ReconcileImports, RefreshTrack, RetryImport}
  alias Bolognesa.Music.Infrastructure.Jobs.RefreshWorker
  alias Bolognesa.Music.Infrastructure.Repositories.EctoImportRepository

  defmodule UnavailableReader do
    def current(_, _), do: {:error, :unavailable}
  end

  defmodule StaleRepository do
    def apply_observation(_, _), do: {:ok, :stale}
  end

  defmodule FailedExhaustionRepository do
    defdelegate begin_attempt(file_id, revision, job_id), to: EctoImportRepository
    def fail_attempt(_, _), do: {:error, :unavailable}
  end

  defmodule UnavailableRetryRepository do
    def request_retry_with_result(_), do: {:error, :unavailable}
  end

  defmodule UnavailableAdmissionRepository do
    def begin_attempt(_, _, _), do: {:error, :unavailable}
  end

  defmodule StalingReader do
    def current(file_id, _) do
      file = Repo.get!(MediaFileSchema, file_id)
      Repo.update!(Ecto.Changeset.change(file, revision: file.revision + 1))
      {:error, :unavailable}
    end
  end

  defmodule CrashingReader do
    def current(_, _), do: raise("private /media/path title token-secret")
  end

  defmodule PartialRecoveryRepository do
    def reconcile_jobs_with_summary(_),
      do: {:error, :unavailable, %{recovered_count: 2, library_ids: [1]}}
  end

  setup do
    id = {__MODULE__, make_ref()}

    events =
      for resource <- [:import, :reconciliation],
          outcome <- [:requested, :started, :completed, :stale, :retryable, :failed, :recovered],
          do: [:bolognesa, :music, resource, outcome]

    :ok = :telemetry.attach_many(id, events, &__MODULE__.capture/4, self())
    on_exit(fn -> :telemetry.detach(id) end)
    :ok
  end

  def capture(event, measurements, metadata, pid) do
    if self() == pid, do: send(pid, {:music_event, event, measurements, metadata})
  end

  test "admitted jobs correlate starts and committed imports without exposing media or tokens" do
    fixture = music_fixture(tags: %{"title" => "secret title"})
    job = request_job(fixture)
    assert :ok = RefreshWorker.perform(%{job | attempt: 2})

    assert_receive {:music_event, [:bolognesa, :music, :import, :started], %{count: 1},
                    %{job_id: job_id, attempt: 2, file_id: file_id, revision: 1}}

    assert job_id == job.id
    assert file_id == fixture.file.id

    assert_receive {:music_event, [:bolognesa, :music, :import, :completed],
                    %{count: 1, duration_ms: duration}, metadata}

    assert duration >= 0
    assert metadata.job_id == job.id
    assert metadata.attempt == 2
    assert metadata.result == :imported
    assert metadata.library_id == fixture.library.id
    refute inspect(metadata) =~ fixture.inspection.token
    refute inspect(metadata) =~ "secret title"
    refute_receive {:music_event, _, _, _}
  end

  test "unadmitted jobs are stale and never claim an attempt start" do
    fixture = music_fixture()
    {:ok, job} = Oban.insert(RefreshWorker.new(%{file_id: fixture.file.id, revision: 1}))
    assert :ok = RefreshWorker.perform(%{Repo.get!(Oban.Job, job.id) | attempt: 1})
    assert_receive {:music_event, [:bolognesa, :music, :import, :stale], _, %{job_id: job_id}}
    assert job_id == job.id
    refute_receive {:music_event, _, _, _}
  end

  test "stale writes are observed before successful return normalization" do
    fixture = music_fixture()
    reader = Bolognesa.Music.Infrastructure.Readers.EctoObservationsReader
    assert :ok = RefreshTrack.call(fixture.file.id, 1, reader, StaleRepository)
    assert_receive {:music_event, [:bolognesa, :music, :import, :stale], _, _}
    refute_receive {:music_event, _, _, _}
  end

  test "unavailable imports emit retryable outcomes" do
    assert {:error, :unavailable} = RefreshTrack.call(1, 1, UnavailableReader, StaleRepository)

    assert_receive {:music_event, [:bolognesa, :music, :import, :retryable], _,
                    %{reason: :storage_unavailable}}

    refute_receive {:music_event, _, _, _}
  end

  test "rolled back handoffs do not announce requested or completed imports" do
    fixture = music_fixture()

    assert {:error, :rollback} =
             Repo.transaction(fn ->
               Music.request_import_in_transaction!(Repo, %{
                 file_id: fixture.file.id,
                 revision: 1,
                 inspection_token: fixture.inspection.token
               })

               Repo.rollback(:rollback)
             end)

    refute_receive {:music_event, _, _, _}
    refute Repo.get_by(MusicImportSchema, media_file_id: fixture.file.id)
  end

  test "only accepted explicit retries announce persisted requests" do
    fixture = music_fixture()
    assert {:error, :forbidden} = Music.retry_import(nil, fixture.file.id)
    refute_receive {:music_event, _, _, _}
    assert :ok = Music.retry_import(fixture.actor, fixture.file.id)

    assert_receive {:music_event, [:bolognesa, :music, :import, :requested], _,
                    %{operation: :retry, file_id: file_id, user_id: user_id}}

    assert file_id == fixture.file.id
    assert user_id == fixture.actor.id
    assert :ok = Music.retry_import(fixture.actor, fixture.file.id)
    refute_receive {:music_event, _, _, _}
  end

  test "reconciliation counts only committed changes and remains quiet when idle" do
    fixture = music_fixture()
    job = request_job(fixture)
    Repo.update!(change(job, state: "discarded"))

    assert :ok =
             ReconcileImports.call(
               DateTime.utc_now(),
               EctoImportRepository
             )

    assert_receive {:music_event, [:bolognesa, :music, :reconciliation, :recovered],
                    %{recovered_count: 1, changed_library_count: 1}, _}

    assert Repo.get_by!(MusicImportSchema, media_file_id: fixture.file.id).state == :failed

    assert :ok =
             ReconcileImports.call(
               DateTime.utc_now(),
               EctoImportRepository
             )

    refute_receive {:music_event, _, _, _}
  end

  test "exhaustion emits terminal failure only after the import state is persisted" do
    fixture = music_fixture()
    job = request_job(fixture)

    assert {:error, :unavailable} =
             RefreshWorker.perform(
               %{job | attempt: job.max_attempts},
               EctoImportRepository,
               UnavailableReader,
               StaleRepository
             )

    assert_receive {:music_event, [:bolognesa, :music, :import, :started], _, _}

    assert_receive {:music_event, [:bolognesa, :music, :import, :retryable], _,
                    %{failure_stage: :import}}

    assert_receive {:music_event, [:bolognesa, :music, :import, :failed], _,
                    %{reason: :attempts_exhausted, failure_stage: :exhaustion}}

    assert Repo.get_by!(MusicImportSchema, media_file_id: fixture.file.id).state == :failed
    refute_receive {:music_event, _, _, _}
  end

  test "unpersisted exhaustion remains retryable" do
    fixture = music_fixture()
    job = request_job(fixture)

    assert {:error, :unavailable} =
             RefreshWorker.perform(
               %{job | attempt: job.max_attempts},
               FailedExhaustionRepository,
               UnavailableReader,
               StaleRepository
             )

    assert_receive {:music_event, [:bolognesa, :music, :import, :started], _, _}

    assert_receive {:music_event, [:bolognesa, :music, :import, :retryable], _,
                    %{failure_stage: :import}}

    assert_receive {:music_event, [:bolognesa, :music, :import, :retryable], _,
                    %{failure_stage: :exhaustion}}

    assert Repo.get_by!(MusicImportSchema, media_file_id: fixture.file.id).state == :running
    refute_receive {:music_event, _, _, _}
  end

  test "escaped exceptions expose only safe failure enums and explicit job correlation" do
    fixture = music_fixture()
    job = request_job(fixture)

    assert {:error, :unexpected_failure} =
             RefreshWorker.perform(
               %{job | attempt: 1},
               EctoImportRepository,
               CrashingReader,
               StaleRepository
             )

    assert_receive {:music_event, [:bolognesa, :music, :import, :started], _, _}
    assert_receive {:music_event, [:bolognesa, :music, :import, :failed], _, metadata}
    assert metadata.reason == :unexpected_failure
    assert metadata.job_id == job.id
    refute inspect(metadata) =~ "private"
    refute inspect(metadata) =~ "token-secret"
    refute_receive {:music_event, _, _, _}
  end

  test "partial recovery preserves committed counts before reporting unavailable work" do
    assert {:error, :unavailable} =
             ReconcileImports.call(
               DateTime.utc_now(),
               PartialRecoveryRepository
             )

    assert_receive {:music_event, [:bolognesa, :music, :reconciliation, :recovered],
                    %{recovered_count: 2, changed_library_count: 1}, _}

    assert_receive {:music_event, [:bolognesa, :music, :reconciliation, :retryable],
                    %{recovered_count: 2, changed_library_count: 1},
                    %{reason: :storage_unavailable}}

    refute_receive {:music_event, _, _, _}
  end

  test "admission failure never claims an actual attempt started" do
    fixture = music_fixture()
    job = request_job(fixture)

    assert {:error, :storage_unavailable} =
             RefreshWorker.perform(
               %{job | attempt: 1},
               UnavailableAdmissionRepository,
               UnavailableReader,
               StaleRepository
             )

    assert_receive {:music_event, [:bolognesa, :music, :import, :retryable], _,
                    %{failure_stage: :admission}}

    assert Repo.get_by!(MusicImportSchema, media_file_id: fixture.file.id).state == :pending
    refute_receive {:music_event, _, _, _}
  end

  test "a stale exhaustion write never claims a terminal failure" do
    fixture = music_fixture()
    job = request_job(fixture)

    assert {:error, :unavailable} =
             RefreshWorker.perform(
               %{job | attempt: job.max_attempts},
               EctoImportRepository,
               StalingReader,
               StaleRepository
             )

    assert_receive {:music_event, [:bolognesa, :music, :import, :started], _, _}

    assert_receive {:music_event, [:bolognesa, :music, :import, :retryable], _,
                    %{failure_stage: :import}}

    assert_receive {:music_event, [:bolognesa, :music, :import, :stale], _,
                    %{failure_stage: :exhaustion}}

    refute_receive {:music_event, _, _, _}
  end

  test "retrying a job keeps its correlation and records the new attempt number" do
    fixture = music_fixture()
    job = request_job(fixture)

    assert {:error, :unavailable} =
             RefreshWorker.perform(
               %{job | attempt: 1},
               EctoImportRepository,
               UnavailableReader,
               StaleRepository
             )

    assert_receive {:music_event, [:bolognesa, :music, :import, :started], _,
                    %{job_id: first_job_id, attempt: 1}}

    assert_receive {:music_event, [:bolognesa, :music, :import, :retryable], _,
                    %{job_id: ^first_job_id, attempt: 1}}

    assert :ok = RefreshWorker.perform(%{job | attempt: 2})

    assert_receive {:music_event, [:bolognesa, :music, :import, :started], _,
                    %{job_id: ^first_job_id, attempt: 2}}

    assert_receive {:music_event, [:bolognesa, :music, :import, :completed], _,
                    %{job_id: ^first_job_id, attempt: 2}}

    refute_receive {:music_event, _, _, _}
  end

  test "obsolete inspection tokens are suppressed without disclosing either token" do
    fixture = music_fixture()
    assert :ok = Music.refresh_track(fixture.file.id, 1, "private old token")
    assert_receive {:music_event, [:bolognesa, :music, :import, :stale], _, metadata}
    refute inspect(metadata) =~ "private"
    refute inspect(metadata) =~ fixture.inspection.token
    refute_receive {:music_event, _, _, _}
  end

  test "failed retry persistence reports unavailable without announcing a request" do
    fixture = music_fixture()

    assert {:error, :unavailable} =
             RetryImport.call(
               fixture.actor,
               fixture.file.id,
               UnavailableRetryRepository
             )

    assert_receive {:music_event, [:bolognesa, :music, :import, :retryable], _,
                    %{failure_stage: :retry, reason: :storage_unavailable}}

    refute_receive {:music_event, _, _, _}
  end

  test "recovery counts committed import rows separately from changed libraries" do
    first = music_fixture()
    second = music_fixture(relative_path: "other/second.mp3")
    Repo.update!(change(second.file, library_id: first.library.id))
    first_job = request_job(first)
    second_job = request_job(second)
    Repo.update!(change(first_job, state: "discarded"))
    {:ok, _} = EctoImportRepository.begin_attempt(second.file.id, 1, second_job.id)

    assert {:ok, %{recovered_count: 2, library_ids: [library_id]}} =
             EctoImportRepository.reconcile_jobs_with_summary(DateTime.utc_now())

    assert library_id == first.library.id
    assert Repo.get_by!(MusicImportSchema, media_file_id: first.file.id).state == :failed
    assert Repo.get_by!(MusicImportSchema, media_file_id: second.file.id).state == :pending

    assert {:ok, %{recovered_count: 0, library_ids: []}} =
             EctoImportRepository.reconcile_jobs_with_summary(DateTime.utc_now())

    refute_receive {:music_event, _, _, _}
  end

  defp request_job(fixture) do
    {:ok, :requested} =
      Repo.transaction(fn ->
        Music.request_import_in_transaction!(Repo, %{
          file_id: fixture.file.id,
          revision: 1,
          inspection_token: fixture.inspection.token
        })
      end)

    state = Repo.get_by!(MusicImportSchema, media_file_id: fixture.file.id)
    Repo.get!(Oban.Job, state.job_id)
  end
end
