defmodule Bolognesa.Series.IdentificationOutboxTest do
  alias Bolognesa.Infrastructure.Persistence.EpisodeSchema
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.SeasonSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationEventSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesSchema
  alias Bolognesa.Libraries.Domain.ValueObjects.Files.NewMediaFile
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoScanRepository
  alias Bolognesa.Series.Domain.ValueObjects.EpisodeSelection
  alias Bolognesa.Series.Infrastructure.Jobs.OutboxDispatcher
  alias Bolognesa.Series.Infrastructure.Repositories.EctoIdentificationRepository, as: Repository
  alias Bolognesa.Series.Infrastructure.Repositories.EctoOutboxRepository
  alias Bolognesa.Series.Infrastructure.Repositories.EctoRequestWriter
  alias Bolognesa.Test.SyntheticSeriesProvider
  alias Ecto.Adapters.SQL
  alias SQL.Sandbox
  use Bolognesa.DataCase, async: false
  use Oban.Testing, repo: Bolognesa.Repo

  test "requesting an automatic match preserves candidates and clears associations" do
    {event, _scan} = pending_event()
    old = confirm_series(event)
    entry = %{file_id: event.media_file_id, revision: old.observed_revision, requested?: true}

    assert {:ok, 0} =
             Repo.transaction(fn ->
               EctoRequestWriter.request_batch!(Repo, [%{entry | requested?: false}])
             end)

    assert {:ok, ^old} = Repository.get(event.media_file_id)

    assert {:ok, 1} =
             Repo.transaction(fn ->
               EctoRequestWriter.request_batch!(Repo, [entry])
             end)

    assert {:ok, requested} = Repository.get(event.media_file_id)
    assert requested.state == :pending
    assert requested.episode_ids == []
    assert requested.origin == :automatic
    assert requested.candidate_data == old.candidate_data
    assert requested.observed_revision == old.observed_revision
    refute requested.token == old.token
    assert is_nil(requested.started_at)
    assert is_nil(requested.finished_at)
    assert Repo.aggregate(SeriesIdentificationEventSchema, :count) == 2
  end

  @tag committed: true
  test "a rejected request event rolls back a new or renewed decision and entries" do
    Sandbox.unboxed_run(Repo, fn ->
      for mode <- [:new, :renew] do
        {event, scan} = pending_event()
        file = Repo.get!(MediaFileSchema, event.media_file_id)
        previous = prepare_request(mode, event)
        event_count = Repo.aggregate(SeriesIdentificationEventSchema, :count)

        SQL.query!(Repo, """
        ALTER TABLE series_identification_events ADD CONSTRAINT identification_refactor_reject_event
        CHECK (media_file_id <> #{file.id}) NOT VALID
        """)

        try do
          assert_raise Ecto.ConstraintError, fn ->
            Repo.transaction(fn ->
              EctoRequestWriter.request_batch!(Repo, [
                %{file_id: file.id, revision: file.revision, requested?: true}
              ])
            end)
          end

          assert Repository.get(file.id) == previous_result(previous)
          assert Repo.aggregate(SeriesIdentificationEventSchema, :count) == event_count
        after
          SQL.query!(
            Repo,
            "ALTER TABLE series_identification_events DROP CONSTRAINT identification_refactor_reject_event"
          )

          cleanup(scan)
          cleanup_series(previous)
        end
      end
    end)
  end

  test "delivers one committed event and leaves none pending" do
    {event, _scan} = pending_event()

    assert {:ok, 1} = EctoOutboxRepository.dispatch_batch(25)
    assert {:ok, 0} = EctoOutboxRepository.dispatch_batch(25)
    assert %DateTime{} = Repo.get!(SeriesIdentificationEventSchema, event.id).delivered_at

    assert [%Oban.Job{args: %{"file_id" => file_id, "token" => token}}] =
             all_enqueued(queue: "identifications")

    assert file_id == event.media_file_id
    assert token == event.token
  end

  test "supervised dispatcher recovers an event created while stopped" do
    {event, _scan} = pending_event()

    pid =
      start_supervised!(
        {OutboxDispatcher, name: :TestIdentificationDispatcher, interval_ms: 60_000}
      )

    _state = :sys.get_state(pid)
    assert %DateTime{} = Repo.get!(SeriesIdentificationEventSchema, event.id).delivered_at
    assert length(all_enqueued(queue: "identifications")) == 1
  end

  @tag committed: true
  test "failed Oban insert leaves event pending" do
    Sandbox.unboxed_run(Repo, fn ->
      {event, scan} = pending_event()

      SQL.query!(Repo, """
      ALTER TABLE oban_jobs ADD CONSTRAINT identification_test_reject_worker
      CHECK (worker <> 'Bolognesa.Series.Infrastructure.Jobs.IdentificationWorker') NOT VALID
      """)

      try do
        assert {:error, :unavailable} = EctoOutboxRepository.dispatch_batch(25)
        assert is_nil(Repo.get!(SeriesIdentificationEventSchema, event.id).delivered_at)
      after
        SQL.query!(
          Repo,
          "ALTER TABLE oban_jobs DROP CONSTRAINT identification_test_reject_worker"
        )

        cleanup(scan)
      end
    end)
  end

  @tag committed: true
  test "failure after Oban insert rolls back the job and leaves the event pending" do
    Sandbox.unboxed_run(Repo, fn ->
      {event, scan} = pending_event()

      SQL.query!(Repo, """
      ALTER TABLE series_identifications ADD CONSTRAINT identification_test_reject_job_link
      CHECK (job_id IS NULL) NOT VALID
      """)

      try do
        assert {:error, :unavailable} = EctoOutboxRepository.dispatch_batch(25)
        assert is_nil(Repo.get!(SeriesIdentificationEventSchema, event.id).delivered_at)

        assert Repo.aggregate(
                 from(job in Oban.Job, where: job.queue == "identifications"),
                 :count
               ) == 0
      after
        SQL.query!(
          Repo,
          "ALTER TABLE series_identifications DROP CONSTRAINT identification_test_reject_job_link"
        )

        cleanup(scan)
      end
    end)
  end

  @tag committed: true
  test "two dispatchers cannot enqueue the same event" do
    Sandbox.unboxed_run(Repo, fn ->
      {event, scan} = pending_event()
      supervisor = start_supervised!(Task.Supervisor)

      try do
        tasks =
          for _ <- 1..2 do
            Task.Supervisor.async_nolink(supervisor, fn ->
              Sandbox.unboxed_run(Repo, fn ->
                EctoOutboxRepository.dispatch_batch(25)
              end)
            end)
          end

        assert Enum.map(tasks, &Task.await/1) |> Enum.sort() == [{:ok, 0}, {:ok, 1}]
        assert %DateTime{} = Repo.get!(SeriesIdentificationEventSchema, event.id).delivered_at

        assert Repo.aggregate(
                 from(job in Oban.Job, where: job.queue == "identifications"),
                 :count
               ) == 1
      after
        cleanup(scan)
      end
    end)
  end

  defp pending_event do
    library =
      %LibrarySchema{}
      |> LibrarySchema.changeset(%{
        content_type: :series,
        name: "Identification outbox",
        path: "/identification-outbox-#{System.unique_integer([:positive])}"
      })
      |> Repo.insert!()

    {:ok, scan} = EctoScanRepository.request(library.id)
    {:ok, running, _} = EctoScanRepository.begin_attempt(scan.id, 1)

    {:ok, entry} =
      NewMediaFile.new(%{
        relative_path: "video.mp4",
        size_bytes: 5,
        modified_at: ~U[2026-10-07 00:00:00Z]
      })

    {:ok, _} = EctoScanRepository.save_batch(scan.id, running.generation, [entry])

    event =
      Repo.one!(from event in SeriesIdentificationEventSchema, where: is_nil(event.delivered_at))

    {event, scan}
  end

  defp confirm_series(event) do
    {:ok, series} = SyntheticSeriesProvider.details(201)
    {:ok, season} = SyntheticSeriesProvider.season(201, 1)

    {:ok, selection} =
      EpisodeSelection.new(series, season, [1])

    assert :ok = Repository.complete_series(event.media_file_id, event.token, [], selection, nil)

    assert {:ok, decision} = Repository.get(event.media_file_id)
    decision
  end

  defp prepare_request(:renew, event), do: confirm_series(event)

  defp prepare_request(:new, event) do
    Repo.delete_all(
      from row in SeriesIdentificationSchema, where: row.media_file_id == ^event.media_file_id
    )

    Repo.delete!(event)
    nil
  end

  defp previous_result(nil), do: {:error, :not_found}
  defp previous_result(decision), do: {:ok, decision}

  defp cleanup_series(nil), do: :ok

  defp cleanup_series(decision) do
    Repo.delete_all(from row in EpisodeSchema, where: row.id in ^decision.episode_ids)
    Repo.delete_all(SeasonSchema)
    Repo.delete_all(SeriesSchema)
  end

  defp cleanup(scan) do
    Repo.delete_all(
      from job in Oban.Job, where: job.queue in ["identifications", "media_inspections"]
    )

    Repo.delete_all(
      from file in Bolognesa.Infrastructure.Persistence.MediaFileSchema,
        where: file.library_id == ^scan.library_id
    )

    Repo.delete_all(
      from row in Bolognesa.Infrastructure.Persistence.ScanSchema, where: row.id == ^scan.id
    )

    Repo.delete_all(from job in Oban.Job, where: job.id == ^scan.job_id)
    Repo.delete!(Repo.get!(LibrarySchema, scan.library_id))
  end
end
