defmodule Bolognesa.Libraries.InspectionJobsTest do
  use Bolognesa.DataCase, async: false
  alias Bolognesa.Infrastructure.Persistence.{InspectionSchema, LibrarySchema}
  alias Bolognesa.Libraries.Domain.ValueObjects.Files.NewMediaFile
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoScanRepository
  alias Ecto.Adapters.SQL
  alias SQL.Sandbox
  use Oban.Testing, repo: Bolognesa.Repo

  test "a persisted request already has its durable job without a dispatcher" do
    {inspection, _scan} = pending_request()
    job = Repo.get!(Oban.Job, inspection.job_id)
    assert job.args == %{"media_file_id" => inspection.media_file_id, "token" => inspection.token}
    assert job.queue == "media_inspections"
    assert job.max_attempts == 3
  end

  @tag committed: true
  test "failed job linking rolls back inventory and jobs together" do
    Sandbox.unboxed_run(Repo, fn ->
      {inspection, scan} = pending_request()
      running = Repo.get!(Bolognesa.Infrastructure.Persistence.ScanSchema, scan.id)
      before_jobs = Repo.aggregate(Oban.Job, :count)

      SQL.query!(
        Repo,
        "ALTER TABLE media_inspections ADD CONSTRAINT inspection_reject_link CHECK (job_id IS NULL) NOT VALID"
      )

      try do
        {:ok, entry} =
          NewMediaFile.new(%{
            relative_path: "new.mp4",
            size_bytes: 5,
            modified_at: ~U[2026-10-03 00:00:00Z]
          })

        assert {:error, :unavailable} =
                 EctoScanRepository.save_batch(scan.id, running.generation, [entry])

        assert Repo.one!(InspectionSchema) == inspection
        assert Repo.aggregate(Oban.Job, :count) == before_jobs
      after
        SQL.query!(Repo, "ALTER TABLE media_inspections DROP CONSTRAINT inspection_reject_link")
        cleanup(scan)
      end
    end)
  end

  defp pending_request do
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
    inspection = Repo.one!(InspectionSchema)
    {inspection, scan}
  end

  defp cleanup(scan) do
    file_ids =
      Repo.all(
        from file in Bolognesa.Infrastructure.Persistence.MediaFileSchema,
          where: file.library_id == ^scan.library_id,
          select: file.id
      )
      |> Enum.map(&Integer.to_string/1)

    Repo.delete_all(
      from job in Oban.Job,
        where:
          fragment("?->>'media_file_id'", job.args) in ^file_ids or
            fragment("?->>'file_id'", job.args) in ^file_ids
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
