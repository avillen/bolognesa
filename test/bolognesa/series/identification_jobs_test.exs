defmodule Bolognesa.Series.IdentificationJobsTest do
  alias Bolognesa.Infrastructure.Persistence.EpisodeSchema
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.SeasonSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesSchema
  alias Bolognesa.Libraries.Domain.ValueObjects.Files.NewMediaFile
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoScanRepository
  alias Bolognesa.Series.Domain.ValueObjects.EpisodeSelection
  alias Bolognesa.Series.Infrastructure.Repositories.EctoIdentificationRepository, as: Repository
  alias Bolognesa.Series.Infrastructure.Repositories.EctoRequestWriter
  alias Bolognesa.Test.SyntheticSeriesProvider
  alias Ecto.Adapters.SQL
  alias SQL.Sandbox
  use Bolognesa.DataCase, async: false
  use Oban.Testing, repo: Bolognesa.Repo

  test "requesting an automatic match preserves candidates and clears associations" do
    {event, _scan} = pending_request()
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

    assert Repo.aggregate(
             from(j in Oban.Job,
               where: j.worker == "Bolognesa.Series.Infrastructure.Jobs.IdentificationWorker"
             ),
             :count
           ) == 2
  end

  @tag committed: true
  test "a rejected request job rolls back a new or renewed decision and entries" do
    Sandbox.unboxed_run(Repo, fn ->
      for mode <- [:new, :renew] do
        {event, scan} = pending_request()
        file = Repo.get!(MediaFileSchema, event.media_file_id)
        previous = prepare_request(mode, event)

        job_count =
          Repo.aggregate(
            from(j in Oban.Job,
              where: j.worker == "Bolognesa.Series.Infrastructure.Jobs.IdentificationWorker"
            ),
            :count
          )

        SQL.query!(Repo, """
        ALTER TABLE oban_jobs ADD CONSTRAINT identification_refactor_reject_event
        CHECK (worker <> 'Bolognesa.Series.Infrastructure.Jobs.IdentificationWorker') NOT VALID
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

          assert Repo.aggregate(
                   from(j in Oban.Job,
                     where:
                       j.worker == "Bolognesa.Series.Infrastructure.Jobs.IdentificationWorker"
                   ),
                   :count
                 ) == job_count
        after
          SQL.query!(
            Repo,
            "ALTER TABLE oban_jobs DROP CONSTRAINT identification_refactor_reject_event"
          )

          cleanup(scan)
          cleanup_series(previous)
        end
      end
    end)
  end

  @tag committed: true
  test "a rejected job link rolls back a new or renewed decision and entries" do
    Sandbox.unboxed_run(Repo, fn ->
      for mode <- [:new, :renew] do
        {event, scan} = pending_request()
        file = Repo.get!(MediaFileSchema, event.media_file_id)
        previous = prepare_request(mode, event)

        job_count =
          Repo.aggregate(
            from(j in Oban.Job,
              where: j.worker == "Bolognesa.Series.Infrastructure.Jobs.IdentificationWorker"
            ),
            :count
          )

        SQL.query!(Repo, """
        ALTER TABLE series_identifications ADD CONSTRAINT identification_refactor_reject_event
        CHECK (job_id IS NULL) NOT VALID
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

          assert Repo.aggregate(
                   from(j in Oban.Job,
                     where:
                       j.worker == "Bolognesa.Series.Infrastructure.Jobs.IdentificationWorker"
                   ),
                   :count
                 ) == job_count
        after
          SQL.query!(
            Repo,
            "ALTER TABLE series_identifications DROP CONSTRAINT identification_refactor_reject_event"
          )

          cleanup(scan)
          cleanup_series(previous)
        end
      end
    end)
  end

  test "a committed decision already has its matching durable job" do
    {request, _scan} = pending_request()
    job = Repo.get!(Oban.Job, request.job_id)
    assert job.args == %{"file_id" => request.media_file_id, "token" => request.token}
    assert job.queue == "identifications"
    assert job.max_attempts == 3
  end

  test "transaction-aware request writer refuses an unboxed call" do
    Sandbox.unboxed_run(Repo, fn ->
      assert_raise ArgumentError, fn -> EctoRequestWriter.request_batch!(Repo, []) end
    end)
  end

  @tag committed: true
  test "committed requests notify the identification queue" do
    Sandbox.unboxed_run(Repo, fn ->
      :ok = Oban.Notifier.listen(:insert)
      {request, scan} = pending_request()

      try do
        assert_receive {:notification, :insert, %{"queue" => "identifications"}}, 1000
        assert Repo.get!(Oban.Job, request.job_id)
      after
        Oban.Notifier.unlisten(:insert)
        cleanup(scan)
      end
    end)
  end

  defp pending_request do
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

    file = Repo.get_by!(MediaFileSchema, library_id: library.id)
    event = Repo.get_by!(SeriesIdentificationSchema, media_file_id: file.id)

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
