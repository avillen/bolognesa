defmodule Bolognesa.Series.SeriesReviewQueriesTest do
  use Bolognesa.DataCase, async: false
  alias Bolognesa.Identity.Domain.Entities.Actor
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationSchema
  alias Bolognesa.Series
  alias Bolognesa.SeriesFixtures
  @actor %Actor{id: 1, role: :admin}

  test "review queues are separated by library type and a double file is one row" do
    library = SeriesFixtures.library()
    double = SeriesFixtures.file(library.id, "Serie S01E01E02.mkv")
    SeriesFixtures.identify(double, 1, [1, 2])

    Repo.get_by!(SeriesIdentificationSchema, media_file_id: double.id)
    |> Ecto.Changeset.change(needs_review: true)
    |> Repo.update!()

    pending = SeriesFixtures.file(library.id, "Unusable.mkv")

    Repo.insert!(%SeriesIdentificationSchema{
      media_file_id: pending.id,
      observed_revision: 1,
      token: Ecto.UUID.generate(),
      state: :unmatched,
      needs_review: true,
      failure_reason: "unusable_name"
    })

    movie_library = SeriesFixtures.library(:movie)
    movie = SeriesFixtures.file(movie_library.id, "Movie.mkv")

    Repo.insert!(%Bolognesa.Infrastructure.Persistence.MovieIdentificationSchema{
      media_file_id: movie.id,
      observed_revision: 1,
      token: Ecto.UUID.generate(),
      state: :pending
    })

    assert {:ok, page} = Series.list_review_items(@actor, 1)
    assert page.total == 2
    assert length(page.items) == 2
    assert hd(page.items).episode_numbers == [1, 2]
    assert List.last(page.items).failure_reason == "unusable_name"
    assert {:ok, %{total: 1}} = Bolognesa.Movies.list_review_items(@actor, 1)
    assert {:error, :forbidden} = Series.list_review_items(nil, 1)
    assert {:error, :invalid_page} = Series.list_review_items(@actor, 0)
  end

  test "reads an identified file for correction even outside the review queue" do
    library = SeriesFixtures.library()
    file = SeriesFixtures.file(library.id, "Serie S00E01E02.mkv")
    SeriesFixtures.identify(file, 0, [1, 2])

    assert {:ok, %{file_id: id, episode_numbers: [1, 2]}} =
             Series.get_review_item(@actor, file.id)

    assert id == file.id
    assert {:error, :forbidden} = Series.get_review_item(nil, file.id)
    assert {:error, :not_found} = Series.get_review_item(@actor, 9_999_999)
  end
end
