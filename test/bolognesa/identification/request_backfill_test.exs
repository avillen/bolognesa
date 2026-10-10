defmodule Bolognesa.Identification.RequestBackfillTest do
  use Bolognesa.DataCase, async: true

  alias Bolognesa.Identification.Infrastructure.Persistence.EctoRequestWriter

  alias Bolognesa.Persistence.{IdentificationEventSchema, IdentificationSchema}

  alias Bolognesa.Persistence.LibrarySchema
  alias Bolognesa.Persistence.MediaFileSchema

  test "backfills existing available files in bounded id order and is idempotent" do
    first = file_fixture("first.mp4")
    second = file_fixture("second.mp4", first.library_id)

    assert {:ok, first_id, 1} = EctoRequestWriter.backfill_batch(0, 1)
    assert first_id == first.id
    assert {:ok, second_id, 1} = EctoRequestWriter.backfill_batch(first_id, 1)
    assert second_id == second.id
    assert {:ok, ^second_id, 0} = EctoRequestWriter.backfill_batch(second_id, 1)
    assert {:ok, ^second_id, 0} = EctoRequestWriter.backfill_batch(0, 100)
    assert Repo.aggregate(IdentificationSchema, :count, :id) == 2
    assert Repo.aggregate(IdentificationEventSchema, :count, :id) == 2
  end

  test "backfill skips unavailable files" do
    file = file_fixture("missing.mp4")
    file |> Ecto.Changeset.change(availability: :missing) |> Repo.update!()

    assert {:ok, _cursor, 0} = EctoRequestWriter.backfill_batch(0, 10)
    assert Repo.aggregate(IdentificationSchema, :count, :id) == 0
  end

  defp file_fixture(path, library_id \\ nil) do
    library_id =
      library_id ||
        Repo.insert!(%LibrarySchema{
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
