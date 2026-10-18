defmodule Bolognesa.Series.SeriesReviewQueriesTest do
  use Bolognesa.DataCase, async: false
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationSchema
  alias Bolognesa.Series
  alias Bolognesa.SeriesFixtures
  @actor %AuthenticatedUser{id: 1, role: :admin}

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

  test "review query count stays constant as files increase and preserves episode order" do
    library = SeriesFixtures.library()
    first = review_file(library.id, "first.mkv", [2, 1])
    {initial, initial_queries} = count_queries(fn -> Series.list_review_items(@actor, 1) end)
    assert {:ok, %{items: [%{file_id: first_id, episode_numbers: [2, 1]}]}} = initial
    assert first_id == first.id

    second = review_file(library.id, "second.mkv", [1])
    {expanded, expanded_queries} = count_queries(fn -> Series.list_review_items(@actor, 1) end)
    assert {:ok, %{items: items, total: 2}} = expanded

    assert Enum.map(items, &{&1.file_id, &1.episode_numbers}) ==
             [{first.id, [2, 1]}, {second.id, [1]}]

    assert initial_queries > 0
    assert expanded_queries == initial_queries
  end

  defp review_file(library_id, path, numbers) do
    file = SeriesFixtures.file(library_id, path)
    SeriesFixtures.identify(file, 1, numbers)

    Repo.get_by!(SeriesIdentificationSchema, media_file_id: file.id)
    |> Ecto.Changeset.change(needs_review: true)
    |> Repo.update!()

    file
  end

  test "reads an identified file for correction even outside the review queue" do
    library = SeriesFixtures.library()
    file = SeriesFixtures.file(library.id, "Serie S00E01E02.mkv")
    SeriesFixtures.identify(file, 0, [1, 2])

    assert {:ok, %{file_id: id, episode_numbers: [1, 2]}} =
             Series.fetch_review_item(@actor, file.id)

    assert id == file.id
    assert {:error, :forbidden} = Series.fetch_review_item(nil, file.id)
    assert :not_found = Series.fetch_review_item(@actor, 0)
    assert :not_found = Series.fetch_review_item(@actor, 9_999_999)
  end

  defp count_queries(fun) do
    reference = make_ref()

    :ok =
      :telemetry.attach(
        reference,
        [:bolognesa, :repo, :query],
        fn _event, _measurements, _metadata, {owner, tag} ->
          if self() == owner, do: send(owner, {tag, :query})
        end,
        {self(), reference}
      )

    try do
      result = fun.()
      {result, query_count(reference, 0)}
    after
      :telemetry.detach(reference)
    end
  end

  defp query_count(reference, count) do
    receive do
      {^reference, :query} -> query_count(reference, count + 1)
    after
      0 -> count
    end
  end
end
