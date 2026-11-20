defmodule Bolognesa.Movies.IdentificationRequestTest do
  alias Bolognesa.MusicFixtures
  alias Ecto.UUID
  use Bolognesa.DataCase, async: true

  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.MovieIdentificationSchema
  alias Bolognesa.Movies.Domain.ValueObjects.ProviderMovie
  alias Bolognesa.Movies.Infrastructure.Repositories.EctoIdentificationRepository, as: Repository

  test "music is excluded at the explicit request boundary" do
    fixture = MusicFixtures.music_fixture()

    assert {:ok, 0} =
             Repo.transaction(fn ->
               Repository.request_batch!(Repo, [
                 %{file_id: fixture.file.id, revision: 1, requested?: true}
               ])
             end)

    assert Repo.get_by(MovieIdentificationSchema,
             media_file_id: fixture.file.id
           ) == nil

    assert Repo.all(
             from(j in Oban.Job,
               where:
                 j.worker == "Bolognesa.Movies.Infrastructure.Jobs.Workers.IdentificationWorker"
             )
           ) == []
  end

  test "explicit requests preserve an existing manual choice" do
    file = file_fixture("manual.mp4")
    details = %ProviderMovie{provider_id: 81_001, title: "Manual"}
    assert {:ok, manual} = Repository.correct(file.id, file.revision, details)

    assert {:ok, 0} =
             Repo.transaction(fn ->
               Repository.request_batch!(Repo, [
                 %{file_id: file.id, revision: 2, requested?: true}
               ])
             end)

    assert {:ok, ^manual} = Repository.get(file.id)

    assert Repo.aggregate(
             from(j in Oban.Job,
               where:
                 j.worker == "Bolognesa.Movies.Infrastructure.Jobs.Workers.IdentificationWorker"
             ),
             :count
           ) == 0
  end

  defp file_fixture(path, library_id \\ nil) do
    library_id =
      library_id ||
        Repo.insert!(%LibrarySchema{
          name: "Requests",
          path: "/tmp/requests-#{System.unique_integer([:positive])}"
        }).id

    Repo.insert!(%MediaFileSchema{
      library_id: library_id,
      relative_path: path,
      size_bytes: 10,
      modified_at: ~U[2026-10-07 00:00:00.000000Z],
      availability: :available,
      revision: 1,
      last_seen_generation: UUID.generate()
    })
  end
end
