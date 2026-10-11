defmodule Bolognesa.Identification.ReviewQueriesTest do
  use Bolognesa.DataCase, async: false
  alias Bolognesa.Persistence.CatalogEntrySchema

  alias Bolognesa.Identification
  alias Bolognesa.Identification.Application.Dto.{ReviewItem, ReviewPage}
  alias Bolognesa.Identification.Domain.Identification, as: IdentificationDecision
  alias Bolognesa.Identification.Domain.ReviewFile
  alias Bolognesa.Identification.Domain.ReviewMovie
  alias Bolognesa.Identification.Infrastructure.Persistence.EctoReviewReader
  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Persistence.IdentificationSchema
  alias Bolognesa.Persistence.LibrarySchema
  alias Bolognesa.Persistence.MediaFileSchema
  alias Bolognesa.Persistence.MovieSchema

  test "shows pending, failed and manually unidentified files to administrators only" do
    library =
      Repo.insert!(LibrarySchema.changeset(%LibrarySchema{}, %{name: "Review", path: "/review"}))

    for {name, state} <- [
          {"a.mkv", :pending},
          {"b.mkv", :failed},
          {"c.mkv", :manual_unidentified}
        ] do
      file =
        Repo.insert!(
          MediaFileSchema.changeset(%MediaFileSchema{}, %{
            library_id: library.id,
            relative_path: name,
            size_bytes: 1,
            modified_at: DateTime.utc_now(),
            last_seen_generation: Ecto.UUID.generate()
          })
        )

      Repo.insert!(
        IdentificationSchema.changeset(%IdentificationSchema{}, %{
          media_file_id: file.id,
          observed_revision: 1,
          token: Ecto.UUID.generate(),
          state: state,
          origin: if(state == :manual_unidentified, do: :manual, else: nil)
        })
      )
    end

    movie =
      Repo.insert!(
        movie_changeset(%{
          provider: :tmdb,
          provider_id: 42,
          title: "Película dudosa"
        })
      )

    linked_file =
      Repo.insert!(
        MediaFileSchema.changeset(%MediaFileSchema{}, %{
          library_id: library.id,
          relative_path: "d.mkv",
          size_bytes: 1,
          modified_at: DateTime.utc_now(),
          last_seen_generation: Ecto.UUID.generate()
        })
      )

    Repo.insert!(
      IdentificationSchema.changeset(%IdentificationSchema{}, %{
        media_file_id: linked_file.id,
        catalog_entry_id: movie.id,
        observed_revision: 1,
        token: Ecto.UUID.generate(),
        state: :automatic,
        origin: :automatic,
        needs_review: true
      })
    )

    assert {:error, :forbidden} = Identification.list_review_items(nil, 1)

    assert {:ok, %ReviewPage{items: [%ReviewItem{} | _] = items, total: 4}} =
             Identification.list_review_items(%Actor{id: 1, role: :admin}, 1)

    assert Enum.map(items, & &1.filename) == ["a.mkv", "b.mkv", "c.mkv", "d.mkv"]
    assert List.last(items).movie_title == "Película dudosa"

    assert {:ok, {[{%IdentificationDecision{}, file, nil} | _] = entries, 4}} =
             EctoReviewReader.list_review_items(1)

    assert file.__struct__ == ReviewFile
    assert file.relative_path == "a.mkv"

    assert {_, _, %ReviewMovie{id: catalog_entry_id, title: "Película dudosa"}} =
             List.last(entries)

    assert catalog_entry_id == movie.id
  end

  defp movie_changeset(attrs) do
    entry =
      Repo.insert!(
        CatalogEntrySchema.changeset(
          %CatalogEntrySchema{},
          %{kind: :movie, provider: :tmdb, resource_type: :movie, provider_id: attrs.provider_id}
        )
      )

    MovieSchema.changeset(%MovieSchema{id: entry.id}, Map.drop(attrs, [:provider, :provider_id]))
  end
end
