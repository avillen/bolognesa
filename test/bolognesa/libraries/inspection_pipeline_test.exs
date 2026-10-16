defmodule Bolognesa.Libraries.InspectionPipelineTest do
  use Bolognesa.DataCase, async: false
  use Oban.Testing, repo: Bolognesa.Repo

  alias Bolognesa.Accounts.Domain.Entities.Actor
  alias Bolognesa.Infrastructure.Persistence.{InspectionEventSchema, InspectionSchema}
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Libraries
  alias Bolognesa.Libraries.Domain.ReadModels.Scans.InspectionCounts
  alias Bolognesa.Libraries.Infrastructure.Jobs.InspectionWorker
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoInspectionRepository
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoOutboxRepository
  alias Bolognesa.Libraries.Support.SuccessfulMediaProbe

  @admin %Actor{id: 1, name: "Admin", email: "admin@example.com", role: :admin}

  setup do
    root = Application.fetch_env!(:bolognesa, :library_roots) |> hd()
    path = Path.join(root, "pipeline-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    source = Path.join(path, "test.mkv")
    File.write!(source, "controlled media")

    {:ok, library} =
      Libraries.create_library(@admin, %{name: "Pipeline", path: path, content_type: :movie})

    %{library: library, source: source}
  end

  test "first scan probes, identical repeat reuses, forced repeat renews", %{
    library: library,
    source: source
  } do
    before = File.read!(source)
    {:ok, _} = Libraries.start_scan(@admin, library.id)
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :library_scans)
    assert %InspectionCounts{pending: 1} = counts(library.id)
    assert {:ok, 1} = EctoOutboxRepository.dispatch_batch(25)

    first = Repo.one!(InspectionSchema)
    job = Repo.get!(Oban.Job, first.job_id)

    assert :ok =
             InspectionWorker.perform(
               %{job | attempt: 1},
               EctoInspectionRepository,
               SuccessfulMediaProbe
             )

    assert %{state: :succeeded, format: "matroska", duration_ms: 2_500} =
             Repo.get!(InspectionSchema, first.id)

    assert %{succeeded: 1} = counts(library.id)

    {:ok, _} = Libraries.start_scan(@admin, library.id)
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :library_scans)
    assert Repo.aggregate(InspectionEventSchema, :count) == 1
    assert {:ok, 0} = EctoOutboxRepository.dispatch_batch(25)
    assert Repo.get!(InspectionSchema, first.id).token == first.token

    {:ok, forced} = Libraries.start_scan(@admin, library.id, force_inspection?: true)
    assert forced.force_inspection?
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :library_scans)
    renewed = Repo.get!(InspectionSchema, first.id)
    refute renewed.token == first.token
    assert renewed.observed_revision == first.observed_revision
    assert %{pending: 1} = counts(library.id)
    assert File.read!(source) == before
  end

  @tag capture_log: true
  test "an inaccessible source does not mark previously seen files absent", %{
    library: library,
    source: source
  } do
    {:ok, _} = Libraries.start_scan(@admin, library.id)
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :library_scans)
    File.rename!(Path.dirname(source), Path.dirname(source) <> "-hidden")

    try do
      {:ok, _} = Libraries.start_scan(@admin, library.id)
      assert %{cancelled: 1} = Oban.drain_queue(queue: :library_scans)
      assert [%{availability: :available}] = Repo.all(MediaFileSchema)
    after
      File.rename!(Path.dirname(source) <> "-hidden", Path.dirname(source))
    end
  end

  defp counts(library_id) do
    {:ok, result} = Libraries.get_inspection_counts(@admin, library_id)
    result
  end
end
