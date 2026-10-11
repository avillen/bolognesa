defmodule Bolognesa.Identification.CorrectIdentificationTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Identification.Application.UseCases.CorrectMovieIdentification
  alias Bolognesa.Identification.Domain.Entities.Identification
  alias Bolognesa.Identification.Domain.ValueObjects.Movies.MovieDetails
  alias Bolognesa.Identity.Domain.Entities.Actor

  alias Bolognesa.Identification.Infrastructure.Repositories.EctoIdentificationRepository,
    as: Repository

  alias Bolognesa.Infrastructure.Persistence.CatalogEntrySchema
  alias Bolognesa.Infrastructure.Persistence.IdentificationSchema
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.MovieSchema

  defmodule Provider do
    def details(id), do: {:ok, %MovieDetails{provider_id: id, title: "Elegida"}}
  end

  test "admin decision is protected and persists over retry" do
    file = fixture()

    assert {:error, :forbidden} =
             CorrectMovieIdentification.call(nil, file.id, :unidentified, Repository, Provider)

    actor = %Actor{id: 1, role: :admin}

    assert {:ok, %Identification{state: :manual, catalog_entry_ids: [catalog_entry_id]}} =
             CorrectMovieIdentification.call(actor, file.id, {:tmdb, 51}, Repository, Provider)

    assert is_integer(catalog_entry_id)
    assert {:error, :manual_locked} = Repository.retry(file.id)

    assert {:ok, %Identification{state: :manual_unidentified, catalog_entry_ids: []}} =
             CorrectMovieIdentification.call(actor, file.id, :unidentified, Repository, Provider)

    refute Repo.get(MovieSchema, catalog_entry_id)
    refute Repo.get(CatalogEntrySchema, catalog_entry_id)

    assert {:error, :invalid_choice} =
             CorrectMovieIdentification.call(actor, file.id, {:tmdb, 0}, Repository, Provider)
  end

  test "reassignment removes the previous movie after its last version leaves" do
    file = fixture()

    assert {:ok, old} =
             Repository.correct(file.id, %MovieDetails{provider_id: 51, title: "Anterior"})

    [old_id] = old.catalog_entry_ids

    assert {:ok, new} =
             Repository.correct(file.id, %MovieDetails{provider_id: 52, title: "Nueva"})

    [new_id] = new.catalog_entry_ids

    refute Repo.get(MovieSchema, old_id)
    refute Repo.get(CatalogEntrySchema, old_id)
    assert Repo.get(MovieSchema, new_id)
    assert Repo.get(CatalogEntrySchema, new_id)
  end

  test "correction preserves the same movie and movies with another missing version" do
    first = fixture()
    second = fixture()
    details = %MovieDetails{provider_id: 51, title: "Compartida"}
    assert {:ok, original} = Repository.correct(first.id, details)
    [id] = original.catalog_entry_ids
    assert {:ok, %{catalog_entry_ids: [^id]}} = Repository.correct(first.id, details)
    assert {:ok, %{catalog_entry_ids: [^id]}} = Repository.correct(second.id, details)

    second |> Ecto.Changeset.change(availability: :missing) |> Repo.update!()
    assert {:ok, _} = Repository.correct(first.id, :unidentified)
    assert Repo.get(MovieSchema, id)
    assert Repo.get(CatalogEntrySchema, id)
  end

  defp fixture do
    library =
      Repo.insert!(
        LibrarySchema.changeset(%LibrarySchema{}, %{
          name: "Corrections",
          path: "/corrections-#{System.unique_integer([:positive])}"
        })
      )

    file =
      Repo.insert!(
        MediaFileSchema.changeset(%MediaFileSchema{}, %{
          library_id: library.id,
          relative_path: "movie.mkv",
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
        state: :pending
      })
    )

    file
  end
end
