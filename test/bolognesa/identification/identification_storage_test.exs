defmodule Bolognesa.Identification.IdentificationStorageTest do
  use Bolognesa.DataCase, async: true
  alias Bolognesa.Infrastructure.Persistence.CatalogEntrySchema
  alias Bolognesa.Infrastructure.Persistence.{IdentificationEventSchema, IdentificationSchema}

  alias Bolognesa.Identification.Domain.Entities.Identification
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.MovieSchema

  test "manual choice rejects later automatic request" do
    identification = %Identification{
      media_file_id: 1,
      state: :manual_unidentified,
      origin: :manual,
      observed_revision: 1,
      token: Ecto.UUID.generate()
    }

    assert {:error, :manual_locked} =
             Identification.request(identification, 2, Ecto.UUID.generate())
  end

  test "database keeps one movie per provider identity and one identification per file" do
    file = file_fixture()

    movie =
      movie_fixture(42)

    assert_raise Ecto.ConstraintError, fn ->
      Repo.insert!(%CatalogEntrySchema{
        kind: :movie,
        provider: :tmdb,
        resource_type: :movie,
        provider_id: 42
      })
    end

    attrs = %{
      media_file_id: file.id,
      state: :manual,
      origin: :manual,
      observed_revision: 1,
      token: Ecto.UUID.generate()
    }

    Bolognesa.IdentificationFixtures.insert_decision!(attrs, [movie.id])

    assert_raise Ecto.ConstraintError, fn ->
      Repo.insert!(struct(IdentificationSchema, %{attrs | token: Ecto.UUID.generate()}))
    end

    assert Repo.aggregate(IdentificationSchema, :count, :id) == 1
  end

  test "database rejects invalid revision and a relation on an unidentified decision" do
    file = file_fixture()
    movie = movie_fixture(43)

    assert_raise Ecto.ConstraintError, fn ->
      Repo.insert!(%IdentificationSchema{
        media_file_id: file.id,
        state: :pending,
        observed_revision: 0,
        token: Ecto.UUID.generate()
      })
    end

    unidentified =
      Repo.insert!(%IdentificationSchema{
        media_file_id: file.id,
        state: :manual_unidentified,
        origin: :manual,
        observed_revision: 1,
        token: Ecto.UUID.generate()
      })

    assert_raise Postgrex.Error, fn ->
      Repo.insert!(%Bolognesa.Infrastructure.Persistence.IdentificationEntrySchema{
        identification_id: unidentified.id,
        catalog_entry_id: movie.id,
        position: 1
      })
    end
  end

  test "missing physical file retains its movie and decision" do
    file = file_fixture()
    movie = movie_fixture(44)

    identification =
      Bolognesa.IdentificationFixtures.insert_decision!(
        %{
          media_file_id: file.id,
          state: :manual,
          origin: :manual,
          observed_revision: 1,
          token: Ecto.UUID.generate()
        },
        [movie.id]
      )

    file |> Ecto.Changeset.change(availability: :missing) |> Repo.update!()

    assert Repo.get_by!(Bolognesa.Infrastructure.Persistence.IdentificationEntrySchema,
             identification_id: identification.id
           ).catalog_entry_id == movie.id
  end

  test "one event exists for a file and request token" do
    file = file_fixture()
    attrs = %{media_file_id: file.id, token: Ecto.UUID.generate()}
    Repo.insert!(struct(IdentificationEventSchema, attrs))

    assert_raise Ecto.ConstraintError, fn ->
      Repo.insert!(struct(IdentificationEventSchema, attrs))
    end
  end

  defp file_fixture do
    library =
      Repo.insert!(%LibrarySchema{
        name: "Test",
        path: "/tmp/h3-#{System.unique_integer([:positive])}"
      })

    Repo.insert!(%MediaFileSchema{
      library_id: library.id,
      relative_path: "film.mp4",
      size_bytes: 10,
      modified_at: ~U[2026-10-07 00:00:00.000000Z],
      revision: 1,
      availability: :available,
      last_seen_generation: Ecto.UUID.generate()
    })
  end

  defp movie_fixture(provider_id) do
    entry =
      Repo.insert!(%CatalogEntrySchema{
        kind: :movie,
        provider: :tmdb,
        resource_type: :movie,
        provider_id: provider_id
      })

    Repo.insert!(%MovieSchema{id: entry.id, title: "Película"})
  end
end
