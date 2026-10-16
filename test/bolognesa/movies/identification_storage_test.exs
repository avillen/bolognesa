defmodule Bolognesa.Movies.IdentificationStorageTest do
  use Bolognesa.DataCase, async: true

  alias Bolognesa.Infrastructure.Persistence.{
    MovieIdentificationEventSchema,
    MovieIdentificationSchema,
    MovieSchema
  }

  test "provider identities and file decisions are unique and missing files retain their work" do
    file = Bolognesa.SeriesFixtures.file(Bolognesa.SeriesFixtures.library(:movie).id, "Movie.mp4")
    attrs = %{provider: :tmdb, provider_id: 42, title: "Synthetic movie"}
    movie = Repo.insert!(MovieSchema.changeset(%MovieSchema{}, attrs))
    assert {:error, duplicate} = Repo.insert(MovieSchema.changeset(%MovieSchema{}, attrs))
    assert Keyword.has_key?(duplicate.errors, :provider)

    choice = %{
      media_file_id: file.id,
      state: :manual,
      origin: :manual,
      observed_revision: 1,
      token: Ecto.UUID.generate(),
      movie_id: movie.id
    }

    decision =
      Repo.insert!(MovieIdentificationSchema.changeset(%MovieIdentificationSchema{}, choice))

    assert {:error, duplicate} =
             Repo.insert(
               MovieIdentificationSchema.changeset(%MovieIdentificationSchema{}, choice)
             )

    assert Keyword.has_key?(duplicate.errors, :media_file_id)
    Repo.update!(Ecto.Changeset.change(file, availability: :missing))
    assert Repo.get!(MovieIdentificationSchema, decision.id).movie_id == movie.id
    assert Repo.get!(MovieSchema, movie.id)
  end

  test "database rejects invalid choices revisions references and duplicate events" do
    file = Bolognesa.SeriesFixtures.file(Bolognesa.SeriesFixtures.library(:movie).id, "Movie.mp4")

    attrs = %{
      media_file_id: file.id,
      observed_revision: 1,
      token: Ecto.UUID.generate(),
      state: :manual,
      movie_id: nil
    }

    assert {:error, invalid} =
             Repo.insert(MovieIdentificationSchema.changeset(%MovieIdentificationSchema{}, attrs))

    assert Keyword.has_key?(invalid.errors, :state)

    assert {:error, invalid} =
             Repo.insert(
               MovieIdentificationSchema.changeset(%MovieIdentificationSchema{}, %{
                 attrs
                 | state: :pending,
                   movie_id: 9_999_999
               })
             )

    assert Keyword.has_key?(invalid.errors, :state)

    assert {:error, invalid} =
             Repo.insert(
               MovieIdentificationSchema.changeset(%MovieIdentificationSchema{}, %{
                 attrs
                 | movie_id: 9_999_999
               })
             )

    assert Keyword.has_key?(invalid.errors, :movie_id)

    assert {:error, _} =
             Repo.insert(
               MovieIdentificationSchema.changeset(%MovieIdentificationSchema{}, %{
                 attrs
                 | state: :pending,
                   observed_revision: 0
               })
             )

    event = %{media_file_id: file.id, token: Ecto.UUID.generate()}

    Repo.insert!(
      MovieIdentificationEventSchema.changeset(%MovieIdentificationEventSchema{}, event)
    )

    assert {:error, _} =
             Repo.insert(
               MovieIdentificationEventSchema.changeset(%MovieIdentificationEventSchema{}, event)
             )
  end
end
