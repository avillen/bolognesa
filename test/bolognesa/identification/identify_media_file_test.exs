defmodule Bolognesa.Identification.IdentifyMediaFileTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Identification.Application.IdentifyMediaFile

  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository,
    as: Repository

  alias Bolognesa.Identification.Domain.{MovieCandidate, MovieDetails}
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoLibraryRepository.LibrarySchema
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository.MediaFileSchema

  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository.IdentificationSchema

  defmodule Provider do
    def search("Mi pelicula", 2001),
      do: {:ok, [%MovieCandidate{provider_id: 42, title: "Otra pelicula", year: 2002}]}

    def details(42), do: {:ok, %MovieDetails{provider_id: 42, title: "Otra pelicula", year: 2002}}
  end

  test "selects first result and marks a mismatch for review" do
    library =
      Repo.insert!(LibrarySchema.changeset(%LibrarySchema{}, %{name: "Movies", path: "/movies"}))

    file =
      Repo.insert!(
        MediaFileSchema.changeset(%MediaFileSchema{}, %{
          library_id: library.id,
          relative_path: "Mi.pelicula.(2001).mkv",
          size_bytes: 1,
          modified_at: DateTime.utc_now(),
          last_seen_generation: Ecto.UUID.generate()
        })
      )

    token = Ecto.UUID.generate()

    Repo.insert!(
      IdentificationSchema.changeset(%IdentificationSchema{}, %{
        media_file_id: file.id,
        observed_revision: 1,
        token: token,
        state: :pending
      })
    )

    assert :ok = IdentifyMediaFile.call(file.id, token, 1, Repository, Provider)

    assert {:ok, %{state: :automatic, needs_review: true, movie_id: movie_id}} =
             Repository.get(file.id)

    assert is_integer(movie_id)
    assert :ok = IdentifyMediaFile.call(file.id, token, 2, Repository, Provider)
  end
end
