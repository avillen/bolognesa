defmodule Bolognesa.Movies.OwnershipTest do
  use Bolognesa.DataCase, async: false
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.MovieIdentificationSchema
  alias Bolognesa.Movies
  alias Bolognesa.Movies.Infrastructure.Repositories.EctoRequestWriter

  @actor %AuthenticatedUser{id: 1, role: :admin}

  test "public corrections and retries authorize first and reject both foreign content types without writes" do
    for type <- [:series, :music] do
      library = Bolognesa.SeriesFixtures.library(type)
      file = Bolognesa.SeriesFixtures.file(library.id, "Synthetic.mp4")
      assert {:error, :forbidden} = Movies.correct(nil, file.id, :unidentified)
      assert {:error, :forbidden} = Movies.retry(nil, file.id)
      assert {:error, :wrong_content_type} = Movies.correct(@actor, file.id, :unidentified)
      assert {:error, :wrong_content_type} = Movies.retry(@actor, file.id)
    end

    assert Repo.aggregate(MovieIdentificationSchema, :count) == 0

    assert Repo.aggregate(
             from(j in Oban.Job,
               where: j.worker == "Bolognesa.Movies.Infrastructure.Jobs.IdentificationWorker"
             ),
             :count
           ) == 0
  end

  test "mixed requests and backfill filter type before their batch limit" do
    foreign = Bolognesa.SeriesFixtures.library(:series)
    for n <- 1..101, do: Bolognesa.SeriesFixtures.file(foreign.id, "Foreign #{n}.mkv")
    library = Bolognesa.SeriesFixtures.library(:movie)
    file = Bolognesa.SeriesFixtures.file(library.id, "Owned.mkv")

    foreign_file =
      Repo.one!(from row in MediaFileSchema, where: row.library_id == ^foreign.id, limit: 1)

    entries =
      Enum.map([foreign_file, file], &%{file_id: &1.id, revision: &1.revision, requested?: true})

    assert {:ok, 1} =
             Repo.transaction(fn -> Movies.request_batch_in_transaction!(Repo, entries) end)

    assert Repo.get_by(MovieIdentificationSchema, media_file_id: foreign_file.id) == nil
    second = Bolognesa.SeriesFixtures.file(library.id, "Second.mkv")
    assert {:ok, cursor, 0} = EctoRequestWriter.backfill_batch(0, 1)
    assert cursor == file.id
    assert {:ok, next, 1} = EctoRequestWriter.backfill_batch(cursor, 1)
    assert next == second.id
  end
end
