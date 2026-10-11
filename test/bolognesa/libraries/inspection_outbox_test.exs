defmodule Bolognesa.Libraries.InspectionOutboxTest do
  use Bolognesa.DataCase, async: false
  alias Bolognesa.Libraries.Domain.NewMediaFile
  alias Bolognesa.Libraries.Infrastructure.Jobs.OutboxDispatcher
  alias Bolognesa.Libraries.Infrastructure.Persistence.{EctoOutboxRepository, EctoScanRepository}
  alias Bolognesa.Persistence.InspectionEventSchema
  alias Bolognesa.Persistence.InspectionSchema
  alias Bolognesa.Persistence.LibrarySchema
  alias Ecto.Adapters.SQL
  alias SQL.Sandbox
  use Oban.Testing, repo: Bolognesa.Repo

  test "dispatches a committed event once and recovers an event created while stopped" do
    {event, _scan} = pending_event()
    assert {:ok, 1} = EctoOutboxRepository.dispatch_batch(25)
    assert {:ok, 0} = EctoOutboxRepository.dispatch_batch(25)
    assert %DateTime{} = Repo.get!(InspectionEventSchema, event.id).delivered_at

    assert [%Oban.Job{args: %{"media_file_id" => file_id, "token" => token}}] =
             all_enqueued(queue: "media_inspections")

    assert file_id == event.media_file_id
    assert token == event.token
    assert is_integer(Repo.get_by!(InspectionSchema, media_file_id: file_id).job_id)
  end

  test "a supervised dispatcher picks up pending events at startup" do
    {event, _scan} = pending_event()

    pid =
      start_supervised!({OutboxDispatcher, name: :TestInspectionDispatcher, interval_ms: 60_000})

    _state = :sys.get_state(pid)
    assert %DateTime{} = Repo.get!(InspectionEventSchema, event.id).delivered_at
    assert length(all_enqueued(queue: "media_inspections")) == 1
  end

  @tag committed: true
  test "a failed Oban insert keeps the event pending" do
    Sandbox.unboxed_run(Repo, fn ->
      {event, scan} = pending_event()

      SQL.query!(Repo, """
      ALTER TABLE oban_jobs ADD CONSTRAINT inspection_test_reject_worker
      CHECK (worker <> 'Bolognesa.Libraries.Infrastructure.Jobs.InspectionWorker') NOT VALID
      """)

      try do
        assert {:error, :unavailable} = EctoOutboxRepository.dispatch_batch(25)
        assert is_nil(Repo.get!(InspectionEventSchema, event.id).delivered_at)
      after
        SQL.query!(
          Repo,
          "ALTER TABLE oban_jobs DROP CONSTRAINT inspection_test_reject_worker"
        )

        cleanup(scan)
      end
    end)
  end

  @tag committed: true
  test "concurrent dispatchers do not duplicate jobs" do
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
        assert %DateTime{} = Repo.get!(InspectionEventSchema, event.id).delivered_at

        assert Repo.aggregate(
                 from(job in Oban.Job, where: job.queue == "media_inspections"),
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
        name: "Outbox",
        path: "/outbox-#{System.unique_integer([:positive])}"
      })
      |> Repo.insert!()

    {:ok, scan} = EctoScanRepository.request(library.id)
    {:ok, running, _} = EctoScanRepository.begin_attempt(scan.id, 1)

    {:ok, entry} =
      NewMediaFile.new(%{
        relative_path: "video.mp4",
        size_bytes: 5,
        modified_at: ~U[2026-10-03 00:00:00Z]
      })

    {:ok, _} = EctoScanRepository.save_batch(scan.id, running.generation, [entry])
    event = Repo.one!(from event in InspectionEventSchema, where: is_nil(event.delivered_at))
    {event, scan}
  end

  defp cleanup(scan) do
    Repo.delete_all(from job in Oban.Job, where: job.queue == "media_inspections")

    Repo.delete_all(
      from file in Bolognesa.Persistence.MediaFileSchema,
        where: file.library_id == ^scan.library_id
    )

    Repo.delete_all(from row in Bolognesa.Persistence.ScanSchema, where: row.id == ^scan.id)
    Repo.delete_all(from job in Oban.Job, where: job.id == ^scan.job_id)
    Repo.delete!(Repo.get!(LibrarySchema, scan.library_id))
  end
end
