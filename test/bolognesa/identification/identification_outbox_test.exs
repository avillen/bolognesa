defmodule Bolognesa.Identification.IdentificationOutboxTest do
  use Bolognesa.DataCase, async: false
  use Oban.Testing, repo: Bolognesa.Repo

  alias Bolognesa.Identification.Infrastructure.Jobs.OutboxDispatcher
  alias Bolognesa.Identification.Infrastructure.Persistence.EctoOutboxRepository

  alias Bolognesa.Persistence.IdentificationEventSchema

  alias Bolognesa.Libraries.Domain.NewMediaFile
  alias Bolognesa.Persistence.LibrarySchema
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository

  test "delivers one committed event and leaves none pending" do
    {event, _scan} = pending_event()

    assert {:ok, 1} = EctoOutboxRepository.dispatch_batch(25)
    assert {:ok, 0} = EctoOutboxRepository.dispatch_batch(25)
    assert %DateTime{} = Repo.get!(IdentificationEventSchema, event.id).delivered_at

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
    assert %DateTime{} = Repo.get!(IdentificationEventSchema, event.id).delivered_at
    assert length(all_enqueued(queue: "identifications")) == 1
  end

  @tag committed: true
  test "failed Oban insert leaves event pending" do
    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      {event, scan} = pending_event()

      Ecto.Adapters.SQL.query!(Repo, """
      ALTER TABLE oban_jobs ADD CONSTRAINT identification_test_reject_worker
      CHECK (worker <> 'Bolognesa.Identification.Infrastructure.Jobs.IdentificationWorker') NOT VALID
      """)

      try do
        assert {:error, :unavailable} = EctoOutboxRepository.dispatch_batch(25)
        assert is_nil(Repo.get!(IdentificationEventSchema, event.id).delivered_at)
      after
        Ecto.Adapters.SQL.query!(
          Repo,
          "ALTER TABLE oban_jobs DROP CONSTRAINT identification_test_reject_worker"
        )

        cleanup(scan)
      end
    end)
  end

  @tag committed: true
  test "failure after Oban insert rolls back the job and leaves the event pending" do
    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      {event, scan} = pending_event()

      Ecto.Adapters.SQL.query!(Repo, """
      ALTER TABLE media_identifications ADD CONSTRAINT identification_test_reject_job_link
      CHECK (job_id IS NULL) NOT VALID
      """)

      try do
        assert {:error, :unavailable} = EctoOutboxRepository.dispatch_batch(25)
        assert is_nil(Repo.get!(IdentificationEventSchema, event.id).delivered_at)

        assert Repo.aggregate(
                 from(job in Oban.Job, where: job.queue == "identifications"),
                 :count
               ) == 0
      after
        Ecto.Adapters.SQL.query!(
          Repo,
          "ALTER TABLE media_identifications DROP CONSTRAINT identification_test_reject_job_link"
        )

        cleanup(scan)
      end
    end)
  end

  @tag committed: true
  test "two dispatchers cannot enqueue the same event" do
    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      {event, scan} = pending_event()
      supervisor = start_supervised!(Task.Supervisor)

      try do
        tasks =
          for _ <- 1..2 do
            Task.Supervisor.async_nolink(supervisor, fn ->
              Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
                EctoOutboxRepository.dispatch_batch(25)
              end)
            end)
          end

        assert Enum.map(tasks, &Task.await/1) |> Enum.sort() == [{:ok, 0}, {:ok, 1}]
        assert %DateTime{} = Repo.get!(IdentificationEventSchema, event.id).delivered_at

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
    event = Repo.one!(from event in IdentificationEventSchema, where: is_nil(event.delivered_at))
    {event, scan}
  end

  defp cleanup(scan) do
    Repo.delete_all(from job in Oban.Job, where: job.queue == "identifications")

    Repo.delete_all(
      from file in Bolognesa.Persistence.MediaFileSchema,
        where: file.library_id == ^scan.library_id
    )

    Repo.delete_all(from row in Bolognesa.Persistence.ScanSchema, where: row.id == ^scan.id)
    Repo.delete_all(from job in Oban.Job, where: job.id == ^scan.job_id)
    Repo.delete!(Repo.get!(LibrarySchema, scan.library_id))
  end
end
