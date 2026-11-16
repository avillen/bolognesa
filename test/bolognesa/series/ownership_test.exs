defmodule Bolognesa.Series.OwnershipTest do
  alias Bolognesa.SeriesFixtures
  use Bolognesa.DataCase, async: false
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationSchema
  alias Bolognesa.Series

  @actor %AuthenticatedUser{id: 1, role: :admin}

  test "public corrections and retries authorize first and reject both foreign content types without writes" do
    for type <- [:movie, :music] do
      library = SeriesFixtures.library(type)
      file = SeriesFixtures.file(library.id, "Synthetic.mp4")
      assert {:error, :forbidden} = Series.correct(nil, file.id, :unidentified)
      assert {:error, :forbidden} = Series.retry(nil, file.id)
      assert {:error, :wrong_content_type} = Series.correct(@actor, file.id, :unidentified)
      assert {:error, :wrong_content_type} = Series.retry(@actor, file.id)
    end

    assert Repo.aggregate(SeriesIdentificationSchema, :count) == 0

    assert Repo.aggregate(
             from(j in Oban.Job,
               where:
                 j.worker == "Bolognesa.Series.Infrastructure.Jobs.Workers.IdentificationWorker"
             ),
             :count
           ) == 0
  end

  test "mixed requests ignore foreign content types" do
    foreign = SeriesFixtures.library(:movie)
    foreign_file = SeriesFixtures.file(foreign.id, "Foreign.mkv")
    library = SeriesFixtures.library(:series)
    file = SeriesFixtures.file(library.id, "Owned.mkv")

    entries =
      Enum.map([foreign_file, file], &%{file_id: &1.id, revision: &1.revision, requested?: true})

    assert {:ok, 1} =
             Repo.transaction(fn -> Series.request_batch_in_transaction!(Repo, entries) end)

    assert Repo.get_by(SeriesIdentificationSchema, media_file_id: foreign_file.id) == nil
  end
end
