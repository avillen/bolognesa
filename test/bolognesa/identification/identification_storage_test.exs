defmodule Bolognesa.Identification.IdentificationStorageTest do
  use Bolognesa.DataCase, async: true

  alias Bolognesa.Identification.Domain.Identification
  alias Bolognesa.Persistence.{IdentificationEventSchema, IdentificationSchema}
  alias Bolognesa.Persistence.LibrarySchema
  alias Bolognesa.Persistence.MediaFileSchema
  alias Bolognesa.Persistence.MovieSchema

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
      Repo.insert!(%MovieSchema{provider: :tmdb, provider_id: 42, title: "Película"})

    assert_raise Ecto.ConstraintError, fn ->
      Repo.insert!(%MovieSchema{provider: :tmdb, provider_id: 42, title: "Duplicada"})
    end

    attrs = %{
      media_file_id: file.id,
      state: :manual,
      origin: :manual,
      movie_id: movie.id,
      observed_revision: 1,
      token: Ecto.UUID.generate()
    }

    Repo.insert!(struct(IdentificationSchema, attrs))

    assert_raise Ecto.ConstraintError, fn ->
      Repo.insert!(struct(IdentificationSchema, %{attrs | token: Ecto.UUID.generate()}))
    end

    assert Repo.aggregate(IdentificationSchema, :count, :id) == 1
  end

  test "database rejects invalid revision and an unidentified choice with a movie" do
    file = file_fixture()
    movie = Repo.insert!(%MovieSchema{provider: :tmdb, provider_id: 43, title: "Película"})

    assert_raise Ecto.ConstraintError, fn ->
      Repo.insert!(%IdentificationSchema{
        media_file_id: file.id,
        state: :pending,
        observed_revision: 0,
        token: Ecto.UUID.generate()
      })
    end

    assert_raise Ecto.ConstraintError, fn ->
      Repo.insert!(%IdentificationSchema{
        media_file_id: file.id,
        movie_id: movie.id,
        state: :manual_unidentified,
        origin: :manual,
        observed_revision: 1,
        token: Ecto.UUID.generate()
      })
    end
  end

  test "missing physical file retains its movie and decision" do
    file = file_fixture()
    movie = Repo.insert!(%MovieSchema{provider: :tmdb, provider_id: 44, title: "Película"})

    identification =
      Repo.insert!(%IdentificationSchema{
        media_file_id: file.id,
        movie_id: movie.id,
        state: :manual,
        origin: :manual,
        observed_revision: 1,
        token: Ecto.UUID.generate()
      })

    file |> Ecto.Changeset.change(availability: :missing) |> Repo.update!()
    assert Repo.get!(IdentificationSchema, identification.id).movie_id == movie.id
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
end
