defmodule Bolognesa.Identification.IdentificationRecoveryTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Identification.Application.IdentifyMediaFile
  alias Bolognesa.Identification.Infrastructure.Jobs.IdentificationWorker

  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository,
    as: Repository

  alias Bolognesa.Persistence.IdentificationSchema

  alias Bolognesa.Persistence.LibrarySchema
  alias Bolognesa.Persistence.MediaFileSchema

  defmodule NoTokenProvider do
    def search(_, _), do: {:error, :not_configured}
  end

  test "permanent provider error is visible and retry gives a new token" do
    {file, token} = fixture()
    assert :ok = IdentifyMediaFile.call(file.id, token, 1, Repository, NoTokenProvider)
    assert {:ok, %{state: :failed, failure_reason: "not_configured"}} = Repository.get(file.id)
    assert {:ok, %{state: :pending, token: new_token}} = Repository.retry(file.id)
    refute token == new_token
    assert :ok = IdentifyMediaFile.call(file.id, token, 2, Repository, NoTokenProvider)
    assert {:ok, %{state: :pending}} = Repository.get(file.id)
  end

  test "revision change makes a late job stale" do
    {file, token} = fixture()
    Repo.update!(MediaFileSchema.changeset(file, %{revision: 2}))
    assert :ok = IdentifyMediaFile.call(file.id, token, 1, Repository, NoTokenProvider)
    assert {:ok, %{state: :pending}} = Repository.get(file.id)
  end

  test "terminal job without a result is reconciled" do
    {file, token} = fixture()

    job =
      Repo.insert!(
        Oban.Job.new(%{file_id: file.id, token: token},
          worker: IdentificationWorker,
          queue: :identifications
        )
      )

    Repo.update_all(from(row in Oban.Job, where: row.id == ^job.id), set: [state: "discarded"])

    Repo.update_all(from(row in IdentificationSchema, where: row.media_file_id == ^file.id),
      set: [job_id: job.id]
    )

    assert :ok = Repository.reconcile_jobs(DateTime.utc_now())

    assert {:ok, %{state: :failed, failure_reason: "attempts_exhausted"}} =
             Repository.get(file.id)
  end

  test "a job queued before manual correction keeps its arguments and is safely discarded" do
    {file, token} = fixture()

    job =
      Repo.insert!(
        Oban.Job.new(%{file_id: file.id, token: token},
          worker: IdentificationWorker,
          queue: :identifications
        )
      )

    assert {:ok, corrected} = Repository.correct(file.id, :unidentified)
    job = Repo.get!(Oban.Job, job.id)
    assert job.args == %{"file_id" => file.id, "token" => token}
    assert :ok = IdentificationWorker.perform(job)
    assert {:ok, current} = Repository.get(file.id)
    assert current == corrected
  end

  defp fixture do
    library =
      Repo.insert!(
        LibrarySchema.changeset(%LibrarySchema{}, %{
          name: "Recovery",
          path: "/recovery-#{System.unique_integer([:positive])}"
        })
      )

    file =
      Repo.insert!(
        MediaFileSchema.changeset(%MediaFileSchema{}, %{
          library_id: library.id,
          relative_path: "Film.mkv",
          size_bytes: 1,
          modified_at: DateTime.utc_now(),
          last_seen_generation: Ecto.UUID.generate()
        })
      )

    token = Ecto.UUID.generate()

    Repo.insert!(
      IdentificationSchema.changeset(%IdentificationSchema{}, %{
        media_file_id: file.id,
        observed_revision: 1,
        token: token,
        state: :pending
      })
    )

    {file, token}
  end
end
