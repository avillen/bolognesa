defmodule Bolognesa.Identification.IdentifyMediaFileTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Identification.Application.IdentifyMediaFile

  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository,
    as: Repository

  alias Bolognesa.Identification.Domain.{MovieCandidate, MovieDetails}
  alias Bolognesa.Persistence.LibrarySchema
  alias Bolognesa.Persistence.MediaFileSchema

  alias Bolognesa.Persistence.IdentificationSchema

  defmodule Provider do
    def search("Mi pelicula", 2001),
      do: {:ok, [%MovieCandidate{provider_id: 42, title: "Otra pelicula", year: 2002}]}

    def details(42), do: {:ok, %MovieDetails{provider_id: 42, title: "Otra pelicula", year: 2002}}
  end

  defmodule ExactProvider do
    def search("Film", nil),
      do: {:ok, [%MovieCandidate{provider_id: 43, title: "Film", year: nil}]}

    def details(43), do: {:ok, %MovieDetails{provider_id: 43, title: "Film", year: nil}}
  end

  defmodule NeverCalledProvider do
    def search(_, _), do: raise("release-only title reached provider")
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

  test "matching title without years completes without review" do
    {file, token} = pending_file("Film.mkv")
    assert :ok = IdentifyMediaFile.call(file.id, token, 1, Repository, ExactProvider)
    assert {:ok, %{state: :automatic, needs_review: false}} = Repository.get(file.id)
  end

  test "release-only filename never reaches provider" do
    {file, token} = pending_file("1080p.WEB-DL.x265.mkv")
    assert :ok = IdentifyMediaFile.call(file.id, token, 1, Repository, NeverCalledProvider)
    assert {:ok, %{state: :failed, failure_reason: "unusable_name"}} = Repository.get(file.id)
  end

  defp pending_file(name) do
    library =
      Repo.insert!(
        LibrarySchema.changeset(%LibrarySchema{}, %{name: name, path: "/#{Ecto.UUID.generate()}"})
      )

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

    token = Ecto.UUID.generate()

    Repo.insert!(
      IdentificationSchema.changeset(%IdentificationSchema{}, %{
        media_file_id: file.id,
        observed_revision: 1,
        token: token,
        state: :pending
      })
    )

    {file, token}
  end
end
