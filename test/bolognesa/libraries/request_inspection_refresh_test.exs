defmodule Bolognesa.Libraries.RequestInspectionRefreshTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Infrastructure.Persistence.{InspectionSchema, LibrarySchema, MediaFileSchema}
  alias Bolognesa.Libraries
  alias Bolognesa.Libraries.Application.UseCases.RequestInspectionRefresh
  alias Bolognesa.Libraries.Domain.ValueObjects.Inspection.TechnicalMedia
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoInspectionRepository
  alias Ecto.Adapters.SQL
  alias SQL.Sandbox

  @admin %AuthenticatedUser{id: 1, name: "Ada", email: "ada@example.com", role: :admin}

  test "authorization precedes repository access" do
    assert {:error, :forbidden} = RequestInspectionRefresh.call(nil, 0, 1, __MODULE__)
  end

  test "validates video file availability and revision" do
    file = file()
    assert {:error, :not_found} = Libraries.request_inspection_refresh(@admin, 0, 1)
    assert {:error, :source_changed} = Libraries.request_inspection_refresh(@admin, file.id, 2)
    Repo.update!(Ecto.Changeset.change(file, availability: :missing))
    assert {:error, :missing} = Libraries.request_inspection_refresh(@admin, file.id, 1)
    music = file(:music)
    assert {:error, :not_found} = Libraries.request_inspection_refresh(@admin, music.id, 1)
    assert Repo.aggregate(Oban.Job, :count) == 0
  end

  test "creates one durable request and coalesces pending and running duplicates" do
    file = file()
    assert {:ok, :enqueued} = Libraries.request_inspection_refresh(@admin, file.id, 1)
    inspection = Repo.get_by!(InspectionSchema, media_file_id: file.id)
    job = Repo.get!(Oban.Job, inspection.job_id)
    assert job.args == %{"media_file_id" => file.id, "token" => inspection.token}
    assert {:ok, :already_pending} = Libraries.request_inspection_refresh(@admin, file.id, 1)
    assert Repo.get!(InspectionSchema, inspection.id) == inspection

    assert {:ok, _, _} =
             EctoInspectionRepository.begin_inspection(file.id, inspection.token, job.id)

    assert {:ok, :already_pending} = Libraries.request_inspection_refresh(@admin, file.id, 1)
    assert Repo.aggregate(Oban.Job, :count) == 1
    assert Repo.get!(MediaFileSchema, file.id) == file
  end

  test "terminal cooldown uses updated_at and refresh invalidates the old worker token" do
    file = file()
    assert {:ok, :enqueued} = Libraries.request_inspection_refresh(@admin, file.id, 1)
    old = Repo.get_by!(InspectionSchema, media_file_id: file.id)
    {:ok, _, _} = EctoInspectionRepository.begin_inspection(file.id, old.token, old.job_id)
    assert :ok = EctoInspectionRepository.fail_inspection(file.id, old.token, :unreadable, 1)
    terminal = Repo.get!(InspectionSchema, old.id)
    assert {:error, :refresh_limited} = Libraries.request_inspection_refresh(@admin, file.id, 1)

    assert {:ok, :enqueued} =
             EctoInspectionRepository.request_refresh(
               file.id,
               1,
               DateTime.add(terminal.updated_at, 31)
             )

    current = Repo.get!(InspectionSchema, old.id)
    refute current.token == old.token
    assert current.state == :pending
    assert current.failure_reason == nil

    assert {:ok, :stale} =
             EctoInspectionRepository.fail_inspection(file.id, old.token, :unreadable, 1)

    assert {:ok, :stale} =
             EctoInspectionRepository.begin_inspection(file.id, old.token, old.job_id)
  end

  test "a pending inspection for an obsolete revision does not prevent refresh" do
    file = file()
    assert {:ok, :enqueued} = Libraries.request_inspection_refresh(@admin, file.id, 1)
    old = Repo.get_by!(InspectionSchema, media_file_id: file.id)
    Repo.update!(Ecto.Changeset.change(file, revision: 2))
    assert {:ok, :enqueued} = Libraries.request_inspection_refresh(@admin, file.id, 2)
    current = Repo.get!(InspectionSchema, old.id)
    assert current.observed_revision == 2
    refute current.token == old.token

    assert {:ok, :stale} =
             EctoInspectionRepository.complete_inspection(file.id, old.token, %TechnicalMedia{
               tracks: []
             })
  end

  @tag committed: true
  test "independent concurrent connections coalesce to one current job" do
    Sandbox.unboxed_run(Repo, fn ->
      file = file()
      parent = self()

      try do
        {:ok, tasks} =
          Repo.transaction(fn ->
            Repo.one!(from row in MediaFileSchema, where: row.id == ^file.id, lock: "FOR UPDATE")

            tasks =
              for _ <- 1..2 do
                Task.async(fn ->
                  Sandbox.unboxed_run(Repo, fn ->
                    %{rows: [[pid]]} = SQL.query!(Repo, "SELECT pg_backend_pid()")
                    send(parent, {:refresh_connection, pid})
                    Libraries.request_inspection_refresh(@admin, file.id, 1)
                  end)
                end)
              end

            pids =
              for _ <- tasks do
                assert_receive {:refresh_connection, pid}, 2_000
                pid
              end

            assert Enum.uniq(pids) == pids
            Enum.each(pids, &await_lock/1)
            tasks
          end)

        results = Enum.map(tasks, &Task.await(&1, 5_000))
        assert Enum.sort(results) == Enum.sort([{:ok, :enqueued}, {:ok, :already_pending}])
        inspection = Repo.get_by!(InspectionSchema, media_file_id: file.id)
        assert Repo.get!(Oban.Job, inspection.job_id).args["token"] == inspection.token

        assert Repo.aggregate(
                 from(job in Oban.Job,
                   where: fragment("?->>'media_file_id'", job.args) == ^to_string(file.id)
                 ),
                 :count
               ) == 1
      after
        cleanup(file)
      end
    end)
  end

  @tag committed: true
  test "failed job linking rolls back request replacement and inserted job" do
    Sandbox.unboxed_run(Repo, fn ->
      file = file()
      {:ok, :enqueued} = Libraries.request_inspection_refresh(@admin, file.id, 1)
      old = Repo.get_by!(InspectionSchema, media_file_id: file.id)

      Repo.update!(
        Ecto.Changeset.change(old,
          state: :failed,
          updated_at: DateTime.add(DateTime.utc_now(), -60)
        )
      )

      before = Repo.get!(InspectionSchema, old.id)
      count = Repo.aggregate(Oban.Job, :count)

      SQL.query!(
        Repo,
        "ALTER TABLE media_inspections ADD CONSTRAINT refresh_reject_link CHECK (job_id IS NULL) NOT VALID"
      )

      try do
        assert {:error, :unavailable} = Libraries.request_inspection_refresh(@admin, file.id, 1)
        assert Repo.get!(InspectionSchema, old.id) == before
        assert Repo.aggregate(Oban.Job, :count) == count
      after
        SQL.query!(
          Repo,
          "ALTER TABLE media_inspections DROP CONSTRAINT refresh_reject_link"
        )

        cleanup(file)
      end
    end)
  end

  defp await_lock(pid, attempts \\ 100)
  defp await_lock(_pid, 0), do: flunk("refresh did not contend on the locked media file")

  defp await_lock(pid, attempts) do
    case SQL.query!(
           Repo,
           "SELECT wait_event_type FROM pg_stat_activity WHERE pid = $1",
           [pid]
         ).rows do
      [["Lock"]] ->
        :ok

      _ ->
        Process.sleep(10)
        await_lock(pid, attempts - 1)
    end
  end

  defp cleanup(file) do
    Repo.delete_all(
      from job in Oban.Job,
        where: fragment("?->>'media_file_id'", job.args) == ^to_string(file.id)
    )

    Repo.delete!(file)
    Repo.delete!(Repo.get!(LibrarySchema, file.library_id))
  end

  defp file(type \\ :movie) do
    library =
      Repo.insert!(%LibrarySchema{
        name: "Refresh",
        path: "/refresh-#{System.unique_integer([:positive])}",
        content_type: type
      })

    Repo.insert!(%MediaFileSchema{
      library_id: library.id,
      relative_path: "synthetic.mp4",
      size_bytes: 5,
      modified_at: ~U[2026-10-03 00:00:00.000000Z],
      last_seen_generation: Ecto.UUID.generate()
    })
  end
end
