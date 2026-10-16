defmodule Bolognesa.Series.RequestBackfillTest do
  use Bolognesa.DataCase, async: true

  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationEventSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationSchema
  alias Bolognesa.Series.Infrastructure.Repositories.EctoIdentificationRepository, as: Repository
  alias Bolognesa.Series.Infrastructure.Repositories.EctoRequestWriter

  test "music is excluded at explicit and backfill request boundaries" do
    fixture = Bolognesa.MusicFixtures.music_fixture()
    assert {:ok, _cursor, 0} = EctoRequestWriter.backfill_batch(0, 100)

    assert {:ok, 0} =
             Repo.transaction(fn ->
               EctoRequestWriter.request_batch!(Repo, [
                 %{file_id: fixture.file.id, revision: 1, requested?: true}
               ])
             end)

    assert Repo.get_by(Bolognesa.Infrastructure.Persistence.SeriesIdentificationSchema,
             media_file_id: fixture.file.id
           ) == nil

    assert Repo.all(Bolognesa.Infrastructure.Persistence.SeriesIdentificationEventSchema) == []
  end

  test "backfills existing available files in bounded id order and is idempotent" do
    first = file_fixture("first.mp4")
    second = file_fixture("second.mp4", first.library_id)

    assert {:ok, first_id, 1} = EctoRequestWriter.backfill_batch(0, 1)
    assert first_id == first.id
    assert {:ok, second_id, 1} = EctoRequestWriter.backfill_batch(first_id, 1)
    assert second_id == second.id
    assert {:ok, ^second_id, 0} = EctoRequestWriter.backfill_batch(second_id, 1)
    assert {:ok, ^second_id, 0} = EctoRequestWriter.backfill_batch(0, 100)
    assert Repo.aggregate(SeriesIdentificationSchema, :count, :id) == 2
    assert Repo.aggregate(SeriesIdentificationEventSchema, :count, :id) == 2
  end

  test "backfill skips unavailable files" do
    file = file_fixture("missing.mp4")
    file |> Ecto.Changeset.change(availability: :missing) |> Repo.update!()

    assert {:ok, _cursor, 0} = EctoRequestWriter.backfill_batch(0, 10)
    assert Repo.aggregate(SeriesIdentificationSchema, :count, :id) == 0
  end

  test "backfill and explicit requests preserve an existing manual choice" do
    file = file_fixture("manual.mp4")
    manual = Bolognesa.SeriesFixtures.identify(file, 1, [1])

    assert {:ok, _cursor, 0} = EctoRequestWriter.backfill_batch(0, 100)

    assert {:ok, 0} =
             Repo.transaction(fn ->
               EctoRequestWriter.request_batch!(Repo, [
                 %{file_id: file.id, revision: 2, requested?: true}
               ])
             end)

    assert {:ok, ^manual} = Repository.get(file.id)
    assert Repo.aggregate(SeriesIdentificationEventSchema, :count) == 0
  end

  defp file_fixture(path, library_id \\ nil) do
    library_id =
      library_id ||
        Repo.insert!(%LibrarySchema{
          content_type: :series,
          name: "Backfill",
          path: "/tmp/backfill-#{System.unique_integer([:positive])}"
        }).id

    Repo.insert!(%MediaFileSchema{
      library_id: library_id,
      relative_path: path,
      size_bytes: 10,
      modified_at: ~U[2026-10-07 00:00:00.000000Z],
      availability: :available,
      revision: 1,
      last_seen_generation: Ecto.UUID.generate()
    })
  end
end
