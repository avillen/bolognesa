defmodule Bolognesa.Movies.IdentifiedMovieWriterTest do
  use Bolognesa.DataCase, async: true
  alias Bolognesa.Infrastructure.Persistence.MovieSchema
  alias Bolognesa.Movies.Domain.ValueObjects.MovieDetails
  alias Bolognesa.Movies.Infrastructure.Repositories.IdentifiedMovieWriter
  import Ecto.Query

  test "reuses the external identity and retains original metadata" do
    entries_before = Repo.aggregate(MovieSchema, :count)
    movies_before = Repo.aggregate(MovieSchema, :count)
    details = %MovieDetails{provider_id: 425, title: " Original "}
    assert {:ok, id} = Repo.transaction(fn -> IdentifiedMovieWriter.upsert!(details) end)
    assert Repo.get!(MovieSchema, id).provider_id == 425
    assert Repo.get!(MovieSchema, id).title == "Original"

    assert {:ok, ^id} =
             Repo.transaction(fn ->
               IdentifiedMovieWriter.upsert!(%{details | title: "Changed"})
             end)

    assert Repo.get!(MovieSchema, id).title == "Original"
    assert Repo.aggregate(MovieSchema, :count) == entries_before + 1
    assert Repo.aggregate(MovieSchema, :count) == movies_before + 1
  end

  test "a later failure rolls back both identity and details" do
    assert {:error, :association_failed} =
             Repo.transaction(fn ->
               IdentifiedMovieWriter.upsert!(%MovieDetails{provider_id: 426, title: "Synthetic"})
               Repo.rollback(:association_failed)
             end)

    assert Repo.aggregate(from(e in MovieSchema, where: e.provider_id == 426), :count) == 0

    assert Repo.aggregate(
             from(m in MovieSchema,
               where: m.provider_id == 426
             ),
             :count
           ) == 0
  end
end
