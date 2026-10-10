defmodule Bolognesa.Catalog.CatalogQueriesTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Catalog
  alias Bolognesa.Catalog.Application.Dto.{MovieDetail, MovieVersion}
  alias Bolognesa.Catalog.Domain.Movie
  alias Bolognesa.Catalog.Infrastructure.Persistence.EctoMovieRepository.MovieSchema
  alias Bolognesa.Identity.Domain.Actor

  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository.IdentificationSchema

  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoLibraryRepository.LibrarySchema
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository.MediaFileSchema

  test "upsert returns a persisted movie and reuses its provider identity" do
    attrs = %{provider: :tmdb, provider_id: 425, title: " La película "}

    assert {:ok, %Movie{} = first} =
             Repo.transaction(fn -> Catalog.upsert_in_transaction!(Repo, attrs) end)

    assert first.id > 0
    assert first.title == "La película"

    assert {:ok, %Movie{id: same_id}} =
             Repo.transaction(fn -> Catalog.upsert_in_transaction!(Repo, attrs) end)

    assert same_id == first.id
    assert Repo.aggregate(MovieSchema, :count) == 1
  end

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

    assert {:ok, %MovieDetail{movie: %Movie{} = catalog_movie, versions: versions}} =
             Catalog.get_movie(actor, movie.id)

    assert catalog_movie.id == movie.id
    assert catalog_movie.title == "Mi pelicula"
    assert length(versions) == 2
    assert Enum.all?(versions, &match?(%MovieVersion{}, &1))
    assert {:ok, %{items: [], total: 0}} = Catalog.list_movies(actor, "No existe", 1)
  end
end
