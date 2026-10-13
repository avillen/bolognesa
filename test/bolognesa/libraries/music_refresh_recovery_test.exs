defmodule Bolognesa.Libraries.MusicRefreshRecoveryTest do
  use Bolognesa.DataCase, async: false
  import Bolognesa.MusicFixtures

  alias Bolognesa.Infrastructure.Persistence.{
    LibrarySchema,
    MediaFileSchema,
    MusicRefreshEventSchema
  }

  alias Bolognesa.Libraries.Infrastructure.Jobs.MusicRefreshDispatcher
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoMusicRefreshOutboxRepository
  alias Ecto.Adapters.SQL
  alias SQL.Sandbox

  test "startup dispatches persisted events without a new scan" do
    fixture = music_fixture()

    event =
      Repo.insert!(
        MusicRefreshEventSchema.changeset(%MusicRefreshEventSchema{}, %{
          media_file_id: fixture.file.id,
          revision: 1,
          inspection_token: fixture.inspection.token
        })
      )

    dispatcher = start_supervised!({MusicRefreshDispatcher, name: nil, interval_ms: 60_000})
    _ = :sys.get_state(dispatcher)
    assert Repo.get!(MusicRefreshEventSchema, event.id).delivered_at != nil
    assert Repo.get!(MusicRefreshEventSchema, event.id).job_id != nil
  end

  test "job insertion rollback preserves events and competing dispatchers deliver each once" do
    supervisor = start_supervised!(Task.Supervisor)

    Sandbox.unboxed_run(Repo, fn ->
      fixtures = for _ <- 1..2, do: music_fixture()
      file_ids = Enum.map(fixtures, & &1.file.id)

      events =
        for fixture <- fixtures do
          Repo.insert!(
            MusicRefreshEventSchema.changeset(%MusicRefreshEventSchema{}, %{
              media_file_id: fixture.file.id,
              revision: 1,
              inspection_token: fixture.inspection.token
            })
          )
        end

      try do
        SQL.query!(
          Repo,
          "ALTER TABLE oban_jobs ADD CONSTRAINT music_test_reject_queue CHECK (queue <> 'music_imports') NOT VALID"
        )

        try do
          assert {:error, :unavailable} = EctoMusicRefreshOutboxRepository.dispatch_batch(100)

          assert Enum.all?(
                   events,
                   &(Repo.get!(MusicRefreshEventSchema, &1.id).delivered_at == nil)
                 )
        after
          SQL.query!(Repo, "ALTER TABLE oban_jobs DROP CONSTRAINT music_test_reject_queue")
        end

        parent = self()

        tasks =
          for _ <- 1..2 do
            Task.Supervisor.async_nolink(supervisor, fn ->
              Sandbox.unboxed_run(Repo, fn ->
                send(parent, {:ready, self()})

                receive do
                  :dispatch -> EctoMusicRefreshOutboxRepository.dispatch_batch(1)
                end
              end)
            end)
          end

        for _ <- tasks, do: assert_receive({:ready, _}, 1000)
        for task <- tasks, do: send(task.pid, :dispatch)
        for task <- tasks, do: assert({:ok, 1} == Task.await(task))
        delivered = Enum.map(events, &Repo.get!(MusicRefreshEventSchema, &1.id))
        assert length(Enum.uniq_by(delivered, & &1.job_id)) == 2
        assert Enum.all?(delivered, &(&1.delivered_at != nil))
      after
        job_ids =
          Repo.all(
            from(e in MusicRefreshEventSchema,
              where: e.media_file_id in ^file_ids,
              select: e.job_id
            )
          )
          |> Enum.reject(&is_nil/1)

        Repo.delete_all(from(e in MusicRefreshEventSchema, where: e.media_file_id in ^file_ids))
        Repo.delete_all(from(f in MediaFileSchema, where: f.id in ^file_ids))
        Repo.delete_all(from(j in Oban.Job, where: j.id in ^job_ids))
        for fixture <- fixtures, do: Repo.delete!(fixture.library)
      end

      for fixture <- fixtures, do: assert(Repo.get(LibrarySchema, fixture.library.id) == nil)
    end)
  end
end
