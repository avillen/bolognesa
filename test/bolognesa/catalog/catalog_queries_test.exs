defmodule Bolognesa.Catalog.CatalogQueriesTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Catalog
  alias Bolognesa.Catalog.Infrastructure.Persistence.EctoMovieRepository.MovieSchema
  alias Bolognesa.Identity.Domain.Actor

  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository.IdentificationSchema

  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoLibraryRepository.LibrarySchema
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository.MediaFileSchema

  test "groups physical versions and retains movies with missing files" do
    actor = %Actor{id: 1, role: :admin}

    library =
      Repo.insert!(
        LibrarySchema.changeset(%LibrarySchema{}, %{name: "Catalog", path: "/catalog"})
      )

    movie =
      Repo.insert!(
        MovieSchema.changeset(%MovieSchema{}, %{
          provider: :tmdb,
          provider_id: 87,
          title: "Mi pelicula"
        })
      )

    for {name, availability} <- [{"a.mkv", :available}, {"b.mkv", :missing}] do
      file =
        Repo.insert!(
          MediaFileSchema.changeset(%MediaFileSchema{}, %{
            library_id: library.id,
            relative_path: name,
            size_bytes: 1,
            modified_at: DateTime.utc_now(),
            availability: availability,
            last_seen_generation: Ecto.UUID.generate()
          })
        )

      Repo.insert!(
        IdentificationSchema.changeset(%IdentificationSchema{}, %{
          media_file_id: file.id,
          movie_id: movie.id,
          observed_revision: 1,
          token: Ecto.UUID.generate(),
          state: :automatic,
          origin: :automatic
        })
      )
    end

    assert {:error, :forbidden} = Catalog.list_movies(nil, "", 1)

    assert {:ok, %{items: [%{id: id, version_count: 2, available_count: 1}], total: 1}} =
             Catalog.list_movies(actor, "Mi", 1)

    assert id == movie.id
    assert {:ok, %{versions: versions}} = Catalog.get_movie(actor, movie.id)
    assert length(versions) == 2
    assert {:ok, %{items: [], total: 0}} = Catalog.list_movies(actor, "No existe", 1)
  end
end
