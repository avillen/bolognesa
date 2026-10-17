defmodule Bolognesa.Libraries.MusicImportHandoffTest do
  use Bolognesa.DataCase, async: false
  use Oban.Testing, repo: Bolognesa.Repo
  import Bolognesa.MusicFixtures
  alias Bolognesa.Infrastructure.Persistence.{InspectionSchema, MusicImportSchema}
  alias Bolognesa.Libraries.Domain.ValueObjects.Inspection.TechnicalMedia
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoInspectionRepository
  alias Bolognesa.Music
  alias Ecto.Adapters.SQL
  alias SQL.Sandbox

  test "accepted audio inspection commits its pending import and job immediately" do
    fixture = music_fixture(inspection_state: :running)

    assert {:ok, :stale} =
             EctoInspectionRepository.complete_inspection(
               fixture.file.id,
               Ecto.UUID.generate(),
               media()
             )

    assert all_enqueued(queue: "music_imports") == []

    assert :ok =
             EctoInspectionRepository.complete_inspection(
               fixture.file.id,
               fixture.inspection.token,
               media()
             )

    state = Repo.get_by!(MusicImportSchema, media_file_id: fixture.file.id)
    assert state.state == :pending
    assert state.inspection_token == fixture.inspection.token
    assert [%Oban.Job{id: job_id, args: args}] = all_enqueued(queue: "music_imports")
    assert job_id == state.job_id
    assert args == %{"file_id" => fixture.file.id, "revision" => 1}
    assert {:ok, :unchanged} = request(fixture)
    assert length(all_enqueued(queue: "music_imports")) == 1
    Repo.update!(change(state, state: :failed))
    assert {:ok, :unchanged} = request(fixture)
    assert Repo.get!(MusicImportSchema, state.id).state == :failed
  end

  test "handoff rejects stale observations, other content types and audio-free inspections" do
    fixture = music_fixture()
    assert {:ok, :stale} = request(fixture, %{inspection_token: Ecto.UUID.generate()})
    assert {:ok, :stale} = request(fixture, %{revision: 2})
    Repo.update!(change(fixture.library, content_type: :movie))
    assert {:ok, :stale} = request(fixture)
    Repo.update!(change(fixture.library, content_type: :music))
    Repo.update!(change(fixture.inspection, tracks: %{"items" => []}))
    assert {:ok, :stale} = request(fixture)
    assert all_enqueued(queue: "music_imports") == []
  end

  test "transaction-aware facade refuses use outside a transaction" do
    # A sandbox checkout is already in a transaction: use an unboxed connection.
    Sandbox.unboxed_run(Repo, fn ->
      assert_raise ArgumentError, fn ->
        Music.request_import_in_transaction!(Repo, %{
          file_id: 1,
          revision: 1,
          inspection_token: Ecto.UUID.generate()
        })
      end
    end)
  end

  @tag committed: true
  test "job insertion or import linking failure rolls back inspection success" do
    Sandbox.unboxed_run(Repo, fn ->
      for constraint <- [
            "ALTER TABLE oban_jobs ADD CONSTRAINT handoff_reject CHECK (queue <> 'music_imports') NOT VALID",
            "ALTER TABLE music_imports ADD CONSTRAINT handoff_reject CHECK (job_id IS NULL) NOT VALID"
          ] do
        fixture = music_fixture(inspection_state: :running)

        table =
          if String.contains?(constraint, "oban_jobs"), do: "oban_jobs", else: "music_imports"

        SQL.query!(Repo, constraint)

        try do
          assert {:error, :unavailable} =
                   EctoInspectionRepository.complete_inspection(
                     fixture.file.id,
                     fixture.inspection.token,
                     media()
                   )

          assert Repo.get!(InspectionSchema, fixture.inspection.id).state == :running
          assert Repo.get_by(MusicImportSchema, media_file_id: fixture.file.id) == nil

          assert Repo.all(
                   from j in Oban.Job,
                     where:
                       fragment("?->>'file_id'", j.args) == ^Integer.to_string(fixture.file.id)
                 ) == []
        after
          SQL.query!(Repo, "ALTER TABLE #{table} DROP CONSTRAINT handoff_reject")

          Repo.delete_all(
            from row in MusicImportSchema, where: row.media_file_id == ^fixture.file.id
          )

          Repo.delete!(fixture.file)
          Repo.delete!(fixture.library)
        end
      end
    end)
  end

  @tag committed: true
  test "concurrent handoffs create one request and one job" do
    supervisor = start_supervised!(Task.Supervisor)

    Sandbox.unboxed_run(Repo, fn ->
      fixture = music_fixture()
      parent = self()

      tasks =
        for _ <- 1..2 do
          Task.Supervisor.async_nolink(supervisor, fn ->
            Sandbox.unboxed_run(Repo, fn ->
              send(parent, {:ready, self()})

              receive do
                :request -> request(fixture)
              end
            end)
          end)
        end

      try do
        for _ <- tasks, do: assert_receive({:ready, _}, 1000)
        for task <- tasks, do: send(task.pid, :request)
        assert Enum.sort(Enum.map(tasks, &Task.await/1)) == [{:ok, :requested}, {:ok, :unchanged}]

        assert [_job] =
                 Repo.all(
                   from j in Oban.Job,
                     where:
                       fragment("?->>'file_id'", j.args) == ^Integer.to_string(fixture.file.id)
                 )
      after
        Repo.delete_all(
          from j in Oban.Job,
            where: fragment("?->>'file_id'", j.args) == ^Integer.to_string(fixture.file.id)
        )

        Repo.delete_all(
          from row in MusicImportSchema, where: row.media_file_id == ^fixture.file.id
        )

        Repo.delete!(fixture.file)
        Repo.delete!(fixture.library)
      end
    end)
  end

  @tag committed: true
  test "committed requests notify Oban so work does not wait for periodic staging" do
    Sandbox.unboxed_run(Repo, fn ->
      fixture = music_fixture()
      :ok = Oban.Notifier.listen(:insert)

      try do
        assert {:ok, :requested} = request(fixture)
        assert_receive {:notification, :insert, %{"queue" => "music_imports"}}, 1000
      after
        Oban.Notifier.unlisten(:insert)

        Repo.delete_all(
          from row in MusicImportSchema, where: row.media_file_id == ^fixture.file.id
        )

        Repo.delete_all(
          from j in Oban.Job,
            where: fragment("?->>'file_id'", j.args) == ^Integer.to_string(fixture.file.id)
        )

        Repo.delete!(fixture.file)
        Repo.delete!(fixture.library)
      end
    end)
  end

  defp request(fixture, overrides \\ %{}) do
    entry =
      Map.merge(
        %{
          file_id: fixture.file.id,
          revision: fixture.file.revision,
          inspection_token: fixture.inspection.token
        },
        overrides
      )

    Repo.transaction(fn -> Music.request_import_in_transaction!(Repo, entry) end)
  end

  defp media do
    {:ok, media} = TechnicalMedia.new(%{format: "mp3", tracks: [%{kind: :audio, codec: "mp3"}]})
    media
  end
end
