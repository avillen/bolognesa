defmodule Bolognesa.Catalog.CatalogEntryStorageTest do
  use Bolognesa.DataCase, async: true
  alias Bolognesa.Infrastructure.Persistence.CatalogEntrySchema

  alias Bolognesa.Infrastructure.Persistence.MovieSchema

  test "external identity validates kind and positive provider ID" do
    for attrs <- [%{provider_id: 0}, %{kind: :unknown}, %{resource_type: :unknown}] do
      changeset =
        CatalogEntrySchema.changeset(struct(CatalogEntrySchema), Map.merge(identity(), attrs))

      refute changeset.valid?
    end
  end

  test "one identity per provider resource" do
    assert {:ok, _} =
             Repo.insert(CatalogEntrySchema.changeset(struct(CatalogEntrySchema), identity()))

    assert {:error, changeset} =
             Repo.insert(CatalogEntrySchema.changeset(struct(CatalogEntrySchema), identity()))

    assert errors_on(changeset).provider_id != []
  end

  test "movie details require an identity and prevent its deletion" do
    assert {:error, changeset} =
             Repo.insert(
               MovieSchema.changeset(%MovieSchema{id: 9_999_999}, %{
                 provider: :tmdb,
                 provider_id: 42,
                 title: "Synthetic"
               })
             )

    assert errors_on(changeset).id != []

    entry = Repo.insert!(CatalogEntrySchema.changeset(struct(CatalogEntrySchema), identity()))

    Repo.insert!(
      MovieSchema.changeset(%MovieSchema{id: entry.id}, %{
        provider: :tmdb,
        provider_id: 42,
        title: "Synthetic"
      })
    )

    assert {:error, changeset} =
             Repo.delete(
               Ecto.Changeset.change(entry)
               |> Ecto.Changeset.foreign_key_constraint(:id, name: :movies_id_fkey)
             )

    assert errors_on(changeset).id != []
  end

  defp identity, do: %{kind: :movie, provider: :tmdb, resource_type: :movie, provider_id: 42}
end
