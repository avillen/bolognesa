defmodule Bolognesa.Identification.SeriesReviewQueriesTest do
  use Bolognesa.DataCase, async: false
  alias Bolognesa.Identification
  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Infrastructure.Persistence.IdentificationSchema
  alias Bolognesa.SeriesFixtures
  @actor %Actor{id: 1, role: :admin}

  test "review queues are separated by library type and a double file is one row" do
    library = SeriesFixtures.library()
    double = SeriesFixtures.file(library.id, "Serie S01E01E02.mkv")
    SeriesFixtures.identify(double, 1, [1, 2])

    Repo.get_by!(IdentificationSchema, media_file_id: double.id)
    |> Ecto.Changeset.change(needs_review: true)
    |> Repo.update!()

    pending = SeriesFixtures.file(library.id, "Unusable.mkv")

    Repo.insert!(%IdentificationSchema{
      media_file_id: pending.id,
      observed_revision: 1,
      token: Ecto.UUID.generate(),
      state: :unmatched,
      needs_review: true,
      failure_reason: "unusable_name"
    })

    movie_library = SeriesFixtures.library(:movie)
    movie = SeriesFixtures.file(movie_library.id, "Movie.mkv")

    Repo.insert!(%IdentificationSchema{
      media_file_id: movie.id,
      observed_revision: 1,
      token: Ecto.UUID.generate(),
      state: :pending
    })

    assert {:ok, page} = Identification.list_series_review_items(@actor, 1)
    assert page.total == 2
    assert length(page.items) == 2
    assert hd(page.items).episode_numbers == [1, 2]
    assert List.last(page.items).failure_reason == "unusable_name"
    assert {:ok, %{total: 1}} = Identification.list_review_items(@actor, 1)
    assert {:error, :forbidden} = Identification.list_series_review_items(nil, 1)
    assert {:error, :invalid_page} = Identification.list_series_review_items(@actor, 0)
  end
end
