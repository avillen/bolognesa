defmodule Bolognesa.Identification.IdentifiedMovieWriterTest do
  use Bolognesa.DataCase, async: true
  alias Bolognesa.Identification.Domain.MovieDetails
  alias Bolognesa.Identification.Infrastructure.Persistence.IdentifiedMovieWriter
  alias Bolognesa.Infrastructure.Persistence.{CatalogEntrySchema, MovieSchema}
  import Ecto.Query

  test "reuses the external identity and retains original metadata" do
    entries_before = Repo.aggregate(CatalogEntrySchema, :count)
    movies_before = Repo.aggregate(MovieSchema, :count)
    details = %MovieDetails{provider_id: 425, title: " Original "}
    assert {:ok, id} = Repo.transaction(fn -> IdentifiedMovieWriter.upsert!(details) end)
    assert Repo.get!(CatalogEntrySchema, id).provider_id == 425
    assert Repo.get!(MovieSchema, id).title == "Original"

    assert {:ok, ^id} =
             Repo.transaction(fn ->
               IdentifiedMovieWriter.upsert!(%{details | title: "Changed"})
             end)

    assert Repo.get!(MovieSchema, id).title == "Original"
    assert Repo.aggregate(CatalogEntrySchema, :count) == entries_before + 1
    assert Repo.aggregate(MovieSchema, :count) == movies_before + 1
  end

  test "a later failure rolls back both identity and details" do
    assert {:error, :association_failed} =
             Repo.transaction(fn ->
               IdentifiedMovieWriter.upsert!(%MovieDetails{provider_id: 426, title: "Synthetic"})
               Repo.rollback(:association_failed)
             end)

    assert Repo.aggregate(from(e in CatalogEntrySchema, where: e.provider_id == 426), :count) == 0

    assert Repo.aggregate(
             from(m in MovieSchema,
               join: e in CatalogEntrySchema,
               on: e.id == m.id,
               where: e.provider_id == 426
             ),
             :count
           ) == 0
  end
end
