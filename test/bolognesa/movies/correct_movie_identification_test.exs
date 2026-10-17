defmodule Bolognesa.Movies.CorrectIdentificationTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.MovieIdentificationSchema
  alias Bolognesa.Infrastructure.Persistence.MovieSchema
  alias Bolognesa.Movies.Application.UseCases.CorrectMovieIdentification
  alias Bolognesa.Movies.Domain.Entities.Identification
  alias Bolognesa.Movies.Domain.ValueObjects.MovieDetails
  alias Bolognesa.Movies.Infrastructure.Repositories.EctoIdentificationRepository, as: Repository

  defmodule Provider do
    def details(id), do: {:ok, %MovieDetails{provider_id: id, title: "Elegida"}}
  end

  test "admin decision is protected and persists over retry" do
    file = fixture()

    assert {:error, :forbidden} =
             CorrectMovieIdentification.call(nil, file.id, :unidentified, Repository, Provider)

    actor = %AuthenticatedUser{id: 1, role: :admin}

    assert {:ok, %Identification{state: :manual, movie_id: movie_id}} =
             CorrectMovieIdentification.call(actor, file.id, {:tmdb, 51}, Repository, Provider)

    assert is_integer(movie_id)
    assert {:error, :manual_locked} = Repository.retry(file.id)

    assert {:ok, %Identification{state: :manual_unidentified, movie_id: nil}} =
             CorrectMovieIdentification.call(actor, file.id, :unidentified, Repository, Provider)

    refute Repo.get(MovieSchema, movie_id)
    refute Repo.get(MovieSchema, movie_id)

    assert {:error, :invalid_choice} =
             CorrectMovieIdentification.call(actor, file.id, {:tmdb, 0}, Repository, Provider)
  end

  test "reassignment removes the previous movie after its last version leaves" do
    file = fixture()

    assert {:ok, old} =
             Repository.correct(file.id, file.revision, %MovieDetails{
               provider_id: 51,
               title: "Anterior"
             })

    old_id = old.movie_id

    assert {:ok, new} =
             Repository.correct(file.id, file.revision, %MovieDetails{
               provider_id: 52,
               title: "Nueva"
             })

    new_id = new.movie_id

    refute Repo.get(MovieSchema, old_id)
    refute Repo.get(MovieSchema, old_id)
    assert Repo.get(MovieSchema, new_id)
    assert Repo.get(MovieSchema, new_id)
  end

  test "correction preserves the same movie and movies with another missing version" do
    first = fixture()
    second = fixture()
    details = %MovieDetails{provider_id: 51, title: "Compartida"}
    assert {:ok, original} = Repository.correct(first.id, first.revision, details)
    id = original.movie_id
    assert {:ok, %{movie_id: ^id}} = Repository.correct(first.id, first.revision, details)
    assert {:ok, %{movie_id: ^id}} = Repository.correct(second.id, second.revision, details)

    second |> Ecto.Changeset.change(availability: :missing) |> Repo.update!()
    assert {:ok, _} = Repository.correct(first.id, first.revision, :unidentified)
    assert Repo.get(MovieSchema, id)
    assert Repo.get(MovieSchema, id)
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
      MovieIdentificationSchema.changeset(%MovieIdentificationSchema{}, %{
        media_file_id: file.id,
        observed_revision: 1,
        token: Ecto.UUID.generate(),
        state: :pending
      })
    )

    file
  end
end
