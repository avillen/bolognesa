defmodule Bolognesa.Movies.OwnershipTest do
  alias Bolognesa.SeriesFixtures
  use Bolognesa.DataCase, async: false
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Infrastructure.Persistence.MovieIdentificationSchema
  alias Bolognesa.Movies

  @actor %AuthenticatedUser{id: 1, role: :admin}

  test "public corrections and retries authorize first and reject both foreign content types without writes" do
    for type <- [:series, :music] do
      library = SeriesFixtures.library(type)
      file = SeriesFixtures.file(library.id, "Synthetic.mp4")
      assert {:error, :forbidden} = Movies.correct(nil, file.id, :unidentified)
      assert {:error, :forbidden} = Movies.retry(nil, file.id)
      assert {:error, :wrong_content_type} = Movies.correct(@actor, file.id, :unidentified)
      assert {:error, :wrong_content_type} = Movies.retry(@actor, file.id)
    end

    assert Repo.aggregate(MovieIdentificationSchema, :count) == 0

    assert Repo.aggregate(
             from(j in Oban.Job,
               where:
                 j.worker == "Bolognesa.Movies.Infrastructure.Jobs.Workers.IdentificationWorker"
             ),
             :count
           ) == 0
  end

  test "mixed requests ignore foreign content types" do
    foreign = SeriesFixtures.library(:series)
    foreign_file = SeriesFixtures.file(foreign.id, "Foreign.mkv")
    library = SeriesFixtures.library(:movie)
    file = SeriesFixtures.file(library.id, "Owned.mkv")

    entries =
      Enum.map([foreign_file, file], &%{file_id: &1.id, revision: &1.revision, requested?: true})

    assert {:ok, 1} =
             Repo.transaction(fn -> Movies.request_batch_in_transaction!(Repo, entries) end)

    assert Repo.get_by(MovieIdentificationSchema, media_file_id: foreign_file.id) == nil
  end
end
