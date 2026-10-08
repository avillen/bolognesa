defmodule Bolognesa.Identification.CorrectIdentificationTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Identification.Application.CorrectIdentification
  alias Bolognesa.Identification.Domain.Identification
  alias Bolognesa.Identification.Domain.MovieDetails

  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository,
    as: Repository

  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository.IdentificationSchema

  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoLibraryRepository.LibrarySchema
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository.MediaFileSchema

  defmodule Provider do
    def details(id), do: {:ok, %MovieDetails{provider_id: id, title: "Elegida"}}
  end

  test "admin decision is protected and persists over retry" do
    file = fixture()

    assert {:error, :forbidden} =
             CorrectIdentification.call(nil, file.id, :unidentified, Repository, Provider)

    actor = %Actor{id: 1, role: :admin}

    assert {:ok, %Identification{state: :manual, movie_id: movie_id}} =
             CorrectIdentification.call(actor, file.id, {:tmdb, 51}, Repository, Provider)

    assert is_integer(movie_id)
    assert {:error, :manual_locked} = Repository.retry(file.id)

    assert {:ok, %Identification{state: :manual_unidentified, movie_id: nil}} =
             CorrectIdentification.call(actor, file.id, :unidentified, Repository, Provider)

    assert {:error, :invalid_choice} =
             CorrectIdentification.call(actor, file.id, {:tmdb, 0}, Repository, Provider)
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
