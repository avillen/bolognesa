defmodule Bolognesa.Music.ImportRecoveryTest do
  use Bolognesa.DataCase, async: true
  import Bolognesa.MusicFixtures

  alias Bolognesa.Infrastructure.Persistence.{
    InspectionSchema,
    MusicImportSchema,
    MusicRefreshEventSchema
  }

  alias Bolognesa.Libraries.Domain.ValueObjects.Inspection.TechnicalMedia
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoInspectionRepository
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoMusicRefreshOutboxRepository
  alias Bolognesa.Music
  alias Bolognesa.Music.Infrastructure.Jobs.RefreshWorker
  alias Bolognesa.Music.Infrastructure.Repositories.EctoImportRepository

  test "obsolete missing-file imports cannot starve current recovery batches" do
    for _ <- 1..100 do
      fixture = music_fixture()
      {:ok, job} = Oban.insert(RefreshWorker.new(%{file_id: fixture.file.id, revision: 1}))
      {:ok, _attempt} = EctoImportRepository.begin_attempt(fixture.file.id, 1, job.id)
      Repo.update!(change(fixture.file, availability: :missing))
      Repo.update!(change(job, state: "discarded"))
    end

    current = music_fixture()
    {:ok, job} = Oban.insert(RefreshWorker.new(%{file_id: current.file.id, revision: 1}))
    {:ok, _attempt} = EctoImportRepository.begin_attempt(current.file.id, 1, job.id)
    Repo.update!(change(job, state: "discarded"))
    assert :ok = EctoImportRepository.reconcile_jobs(DateTime.utc_now())
    assert Repo.get_by!(MusicImportSchema, media_file_id: current.file.id).state == :failed
  end

  test "historical delivered events with no job ID recover without crashing" do
    fixture = music_fixture()

    Repo.insert!(
      MusicRefreshEventSchema.changeset(
        %MusicRefreshEventSchema{},
        %{
          media_file_id: fixture.file.id,
          revision: 1,
          inspection_token: fixture.inspection.token,
          delivered_at: DateTime.utc_now()
        }
      )
    )

    assert :ok = EctoImportRepository.reconcile_jobs(DateTime.utc_now())
    assert Repo.get_by!(MusicImportSchema, media_file_id: fixture.file.id).state == :failed
  end

  test "terminal jobs are recovered even when import never started" do
    fixture = music_fixture(inspection_state: :running)

    {:ok, media} =
      TechnicalMedia.new(%{
        format: "mp3",
        tracks: [%{kind: :audio, codec: "mp3"}]
      })

    assert :ok =
             EctoInspectionRepository.complete_inspection(
               fixture.file.id,
               fixture.inspection.token,
               media
             )

    assert {:ok, 1} =
             EctoMusicRefreshOutboxRepository.dispatch_batch(100)

    job = Repo.one!(from(job in Oban.Job, where: job.queue == "music_imports"))
    Repo.update!(change(job, state: "discarded"))
    assert Repo.get_by(MusicImportSchema, media_file_id: fixture.file.id) == nil
    assert :ok = EctoImportRepository.reconcile_jobs(DateTime.utc_now())
    state = Repo.get_by!(MusicImportSchema, media_file_id: fixture.file.id)
    assert state.state == :failed
    assert state.failure_reason == :attempts_exhausted
  end

  test "duplicate jobs and late failures cannot downgrade successful imports" do
    fixture = music_fixture()
    {:ok, job} = Oban.insert(RefreshWorker.new(%{file_id: fixture.file.id, revision: 1}))
    {:ok, attempt} = EctoImportRepository.begin_attempt(fixture.file.id, 1, job.id)
    assert :ok = Music.refresh_track(fixture.file.id, 1)
    assert {:ok, :stale} = EctoImportRepository.fail_attempt(attempt, :unexpected_failure)
    assert :ok = RefreshWorker.perform(%{Repo.get!(Oban.Job, job.id) | attempt: 1})
    assert Repo.get_by!(MusicImportSchema, media_file_id: fixture.file.id).state == :succeeded
  end

  test "discarded, cancelled, completed and missing jobs become visible terminal failures and retry" do
    for status <- ["discarded", "cancelled", "completed", "missing"] do
      fixture = music_fixture()
      {:ok, job} = Oban.insert(RefreshWorker.new(%{file_id: fixture.file.id, revision: 1}))
      {:ok, _attempt} = EctoImportRepository.begin_attempt(fixture.file.id, 1, job.id)

      if status == "missing",
        do: Repo.delete!(job),
        else: Repo.update!(change(job, state: status))

      assert :ok = EctoImportRepository.reconcile_jobs(DateTime.utc_now())
      failed = Repo.get_by!(MusicImportSchema, media_file_id: fixture.file.id)
      assert failed.state == :failed
      assert failed.failure_reason in [:attempts_exhausted, :unexpected_failure]
      assert {:error, :forbidden} = Music.retry_import(nil, fixture.file.id)
      assert :ok = Music.retry_import(fixture.actor, fixture.file.id)
      retry = Repo.get_by!(MusicImportSchema, media_file_id: fixture.file.id)
      assert retry.state == :pending
      assert retry.job_id != job.id
      assert :ok = RefreshWorker.perform(%{Repo.get!(Oban.Job, retry.job_id) | attempt: 1})
    end
  end

  test "same revision reinspection rejects old attempts and refreshes latest token" do
    fixture = music_fixture()
    {:ok, old_job} = Oban.insert(RefreshWorker.new(%{file_id: fixture.file.id, revision: 1}))
    {:ok, old_attempt} = EctoImportRepository.begin_attempt(fixture.file.id, 1, old_job.id)

    inspection =
      Repo.update!(
        change(fixture.inspection,
          token: Ecto.UUID.generate(),
          music_tags: %{"title" => "Current"}
        )
      )

    assert :ok = Music.retry_import(fixture.actor, fixture.file.id)
    state = Repo.get_by!(MusicImportSchema, media_file_id: fixture.file.id)
    assert state.inspection_token == inspection.token
    assert {:ok, :stale} = EctoImportRepository.fail_attempt(old_attempt, :unexpected_failure)
    assert :ok = RefreshWorker.perform(%{Repo.get!(Oban.Job, state.job_id) | attempt: 1})
    assert Repo.get!(InspectionSchema, inspection.id).token == inspection.token
  end

  test "recovery resets retries but only rescues executions when both timestamps are old" do
    fixture = music_fixture()
    {:ok, job} = Oban.insert(RefreshWorker.new(%{file_id: fixture.file.id, revision: 1}))
    {:ok, _attempt} = EctoImportRepository.begin_attempt(fixture.file.id, 1, job.id)
    Repo.update!(change(job, state: "retryable"))
    assert :ok = EctoImportRepository.reconcile_jobs(DateTime.utc_now())
    assert Repo.get_by!(MusicImportSchema, media_file_id: fixture.file.id).state == :pending
    {:ok, _attempt} = EctoImportRepository.begin_attempt(fixture.file.id, 1, job.id)
    now = DateTime.utc_now()
    Repo.update!(change(job, state: "executing", attempted_at: DateTime.add(now, -120, :second)))
    assert :ok = EctoImportRepository.reconcile_jobs(now)
    assert Repo.get_by!(MusicImportSchema, media_file_id: fixture.file.id).state == :running
    state = Repo.get_by!(MusicImportSchema, media_file_id: fixture.file.id)
    Repo.update!(change(state, started_at: DateTime.add(now, -120, :second)))
    assert :ok = EctoImportRepository.reconcile_jobs(now)
    assert Repo.get_by!(MusicImportSchema, media_file_id: fixture.file.id).state == :failed
  end
end
