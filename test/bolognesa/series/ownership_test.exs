defmodule Bolognesa.Series.OwnershipTest do
  use Bolognesa.DataCase, async: false
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationEventSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationSchema
  alias Bolognesa.Series
  alias Bolognesa.Series.Infrastructure.Repositories.EctoOutboxRepository
  alias Bolognesa.Series.Infrastructure.Repositories.EctoRequestWriter

  @actor %AuthenticatedUser{id: 1, role: :admin}

  test "public corrections and retries authorize first and reject both foreign content types without writes" do
    for type <- [:movie, :music] do
      library = Bolognesa.SeriesFixtures.library(type)
      file = Bolognesa.SeriesFixtures.file(library.id, "Synthetic.mp4")
      assert {:error, :forbidden} = Series.correct(nil, file.id, :unidentified)
      assert {:error, :forbidden} = Series.retry(nil, file.id)
      assert {:error, :wrong_content_type} = Series.correct(@actor, file.id, :unidentified)
      assert {:error, :wrong_content_type} = Series.retry(@actor, file.id)
    end

    assert Repo.aggregate(SeriesIdentificationSchema, :count) == 0
    assert Repo.aggregate(SeriesIdentificationEventSchema, :count) == 0
  end

  test "mixed requests and backfill filter type before their batch limit" do
    foreign = Bolognesa.SeriesFixtures.library(:movie)
    for n <- 1..101, do: Bolognesa.SeriesFixtures.file(foreign.id, "Foreign #{n}.mkv")
    library = Bolognesa.SeriesFixtures.library(:series)
    file = Bolognesa.SeriesFixtures.file(library.id, "Owned.mkv")

    foreign_file =
      Repo.one!(from row in MediaFileSchema, where: row.library_id == ^foreign.id, limit: 1)

    entries =
      Enum.map([foreign_file, file], &%{file_id: &1.id, revision: &1.revision, requested?: true})

    assert {:ok, 1} =
             Repo.transaction(fn -> Series.request_batch_in_transaction!(Repo, entries) end)

    assert Repo.get_by(SeriesIdentificationSchema, media_file_id: foreign_file.id) == nil
    second = Bolognesa.SeriesFixtures.file(library.id, "Second.mkv")
    assert {:ok, cursor, 0} = EctoRequestWriter.backfill_batch(0, 1)
    assert cursor == file.id
    assert {:ok, next, 1} = EctoRequestWriter.backfill_batch(cursor, 1)
    assert next == second.id
  end

  test "outbox type filtering does not spend its batch on foreign events" do
    foreign = Bolognesa.SeriesFixtures.library(:movie)
    foreign_file = Bolognesa.SeriesFixtures.file(foreign.id, "Foreign.mkv")

    bad =
      Repo.insert!(%SeriesIdentificationEventSchema{
        media_file_id: foreign_file.id,
        token: Ecto.UUID.generate()
      })

    owned = Bolognesa.SeriesFixtures.library(:series)
    file = Bolognesa.SeriesFixtures.file(owned.id, "Owned.mkv")

    assert {:ok, 1} =
             Repo.transaction(fn ->
               Series.request_batch_in_transaction!(Repo, [
                 %{file_id: file.id, revision: 1, requested?: true}
               ])
             end)

    assert {:ok, 1} = EctoOutboxRepository.dispatch_batch(1)
    assert Repo.get!(SeriesIdentificationEventSchema, bad.id).delivered_at == nil
    assert Repo.get_by!(SeriesIdentificationSchema, media_file_id: file.id).job_id
  end
end
