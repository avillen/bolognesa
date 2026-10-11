defmodule Bolognesa.Identification.IdentificationRecoveryTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Identification.Application.IdentifyMediaFile
  alias Bolognesa.Identification.Infrastructure.Jobs.IdentificationWorker

  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository,
    as: Repository

  alias Bolognesa.Infrastructure.Persistence.IdentificationSchema

  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema

  defmodule NoTokenProvider do
    def search(_, _), do: {:error, :not_configured}
  end

  test "recovery records reasons for every terminal missing and interrupted job" do
    now = ~U[2026-10-11 12:00:00.000000Z]
    old = DateTime.add(now, -61, :second)

    for state <- ["completed", "cancelled", "discarded", "missing", "executing"] do
      {file, token} = fixture()
      link_job(file, token, state, old, old)
      assert :ok = Repository.reconcile_jobs(now)
      reason = if state == "discarded", do: "attempts_exhausted", else: "unexpected_failure"
      assert {:ok, %{state: :failed, failure_reason: ^reason}} = Repository.get(file.id)
    end
  end

  test "executing jobs require both timestamps strictly older than the cutoff" do
    now = ~U[2026-10-11 12:00:00.000000Z]
    old = DateTime.add(now, -61, :second)
    boundary = DateTime.add(now, -60, :second)

    for {started, attempted} <- [{old, boundary}, {boundary, old}, {nil, old}, {old, nil}] do
      {file, token} = fixture()
      link_job(file, token, "executing", started, attempted)
      assert {:ok, previous} = Repository.get(file.id)
      assert :ok = Repository.reconcile_jobs(now)
      assert {:ok, ^previous} = Repository.get(file.id)
    end
  end

  test "recovery preserves unavailable changed and manually corrected files" do
    now = ~U[2026-10-11 12:00:00.000000Z]

    for change <- [:missing, :revision, :manual] do
      {file, token} = fixture()
      link_job(file, token, "discarded", now, now)
      change_file(change, file)
      assert {:ok, previous} = Repository.get(file.id)
      assert :ok = Repository.reconcile_jobs(now)
      assert {:ok, ^previous} = Repository.get(file.id)
    end
  end

  test "recovery processes at most one hundred decisions in id order" do
    now = ~U[2026-10-11 12:00:00.000000Z]

    files =
      for _ <- 1..101 do
        {file, token} = fixture()
        link_job(file, token, "discarded", now, now)
        file
      end

    last = List.last(files)

    assert :ok = Repository.reconcile_jobs(now)

    assert Repo.aggregate(from(row in IdentificationSchema, where: row.state == :failed), :count) ==
             100

    assert {:ok, %{state: :pending}} = Repository.get(last.id)
    assert :ok = Repository.reconcile_jobs(now)

    assert Repo.aggregate(from(row in IdentificationSchema, where: row.state == :failed), :count) ==
             101
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

  defp link_job(file, token, state, started_at, attempted_at) do
    job =
      Repo.insert!(
        Oban.Job.new(%{file_id: file.id, token: token},
          worker: IdentificationWorker,
          queue: :identifications
        )
      )

    set_job_state(state, job, attempted_at)

    Repo.update_all(from(row in IdentificationSchema, where: row.media_file_id == ^file.id),
      set: [job_id: job.id, started_at: started_at]
    )
  end

  defp set_job_state("missing", job, _attempted_at), do: Repo.delete!(job)

  defp set_job_state(state, job, attempted_at) do
    Repo.update_all(from(row in Oban.Job, where: row.id == ^job.id),
      set: [state: state, attempted_at: attempted_at]
    )
  end

  defp change_file(:missing, file),
    do: file |> Ecto.Changeset.change(availability: :missing) |> Repo.update!()

  defp change_file(:revision, file),
    do: file |> Ecto.Changeset.change(revision: 2) |> Repo.update!()

  defp change_file(:manual, file), do: Repository.correct(file.id, :unidentified)
end
