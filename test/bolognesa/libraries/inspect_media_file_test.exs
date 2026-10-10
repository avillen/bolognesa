defmodule Bolognesa.Libraries.InspectMediaFileTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Libraries.Application.InspectMediaFile
  alias Bolognesa.Libraries.Domain.NewMediaFile
  alias Bolognesa.Persistence.LibrarySchema
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoInspectionRepository
  alias Bolognesa.Persistence.InspectionSchema
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository

  alias Bolognesa.Libraries.Support.{
    BlockingMediaProbe,
    FailingMediaProbe,
    SuccessfulMediaProbe,
    TimeoutMediaProbe
  }

  setup do
    library =
      %LibrarySchema{}
      |> LibrarySchema.changeset(%{
        name: "Inspection",
        path: "/inspection-#{System.unique_integer([:positive])}"
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
    inspection = Repo.one!(InspectionSchema)
    %{inspection: inspection, running: running}
  end

  test "stores normalized success and ignores repeated or stale jobs", %{inspection: inspection} do
    assert :ok =
             InspectMediaFile.call(
               inspection.media_file_id,
               inspection.token,
               1,
               EctoInspectionRepository,
               SuccessfulMediaProbe
             )

    assert {:ok, %{state: :succeeded, format: "matroska", duration_ms: 2_500}} =
             EctoInspectionRepository.get(inspection.media_file_id)

    assert %{"items" => [%{"kind" => "video", "channels" => nil, "language" => nil}]} =
             Repo.get!(InspectionSchema, inspection.id).tracks

    assert :ok =
             InspectMediaFile.call(
               inspection.media_file_id,
               inspection.token,
               1,
               EctoInspectionRepository,
               SuccessfulMediaProbe
             )

    assert :ok =
             InspectMediaFile.call(
               inspection.media_file_id,
               Ecto.UUID.generate(),
               1,
               EctoInspectionRepository,
               FailingMediaProbe
             )

    assert %{state: :succeeded, token: token} =
             Repo.get_by!(InspectionSchema, media_file_id: inspection.media_file_id)

    assert token == inspection.token
  end

  test "records permanent failure without private output", %{inspection: inspection} do
    assert :ok =
             InspectMediaFile.call(
               inspection.media_file_id,
               inspection.token,
               1,
               EctoInspectionRepository,
               FailingMediaProbe
             )

    assert {:ok, %{state: :failed, failure_reason: :invalid_output}} =
             EctoInspectionRepository.get(inspection.media_file_id)
  end

  test "does not publish a result after the file becomes absent", %{
    inspection: inspection,
    running: running
  } do
    assert {:ok, _} = EctoScanRepository.complete(running.id, running.generation)
    {:ok, empty} = EctoScanRepository.request(running.library_id)
    {:ok, current, _} = EctoScanRepository.begin_attempt(empty.id, 1)
    assert {:ok, _} = EctoScanRepository.complete(empty.id, current.generation)

    assert :ok =
             InspectMediaFile.call(
               inspection.media_file_id,
               inspection.token,
               1,
               EctoInspectionRepository,
               SuccessfulMediaProbe
             )

    refute Repo.get_by!(InspectionSchema, media_file_id: inspection.media_file_id).state ==
             :succeeded
  end

  test "a replaced token blocks a result that finishes later", %{
    inspection: inspection,
    running: running
  } do
    Process.register(self(), :inspection_probe_owner)
    supervisor = start_supervised!(Task.Supervisor)

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        InspectMediaFile.call(
          inspection.media_file_id,
          inspection.token,
          1,
          EctoInspectionRepository,
          BlockingMediaProbe
        )
      end)

    assert_receive {:probe_started, pid}, 1_000
    assert {:ok, _} = EctoScanRepository.complete(running.id, running.generation)
    {:ok, forced} = EctoScanRepository.request(running.library_id, true)
    {:ok, force_running, _} = EctoScanRepository.begin_attempt(forced.id, 1)

    {:ok, entry} =
      NewMediaFile.new(%{
        relative_path: "film.mkv",
        size_bytes: 5,
        modified_at: ~U[2026-10-03 00:00:00Z]
      })

    assert {:ok, _} = EctoScanRepository.save_batch(forced.id, force_running.generation, [entry])
    send(pid, :probe_continue)
    assert :ok = Task.await(task)

    assert %{state: :pending, format: nil, token: new_token} =
             Repo.get!(InspectionSchema, inspection.id)

    refute new_token == inspection.token
  end

  test "transient timeout retries and the final attempt becomes visible", %{
    inspection: inspection
  } do
    assert {:error, :timeout} =
             InspectMediaFile.call(
               inspection.media_file_id,
               inspection.token,
               1,
               EctoInspectionRepository,
               TimeoutMediaProbe
             )

    assert Repo.get!(InspectionSchema, inspection.id).state == :running

    assert {:error, :timeout} =
             InspectMediaFile.call(
               inspection.media_file_id,
               inspection.token,
               3,
               EctoInspectionRepository,
               TimeoutMediaProbe
             )

    assert %{state: :failed, failure_reason: :timeout} =
             Repo.get!(InspectionSchema, inspection.id)
  end
end
