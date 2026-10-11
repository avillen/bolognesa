defmodule Bolognesa.Catalog.CatalogQueriesTest do
  use Bolognesa.DataCase, async: false
  alias Bolognesa.Infrastructure.Persistence.CatalogEntrySchema

  alias Bolognesa.Catalog
  alias Bolognesa.Catalog.Application.Dto.MovieDetail
  alias Bolognesa.Catalog.Application.Dto.MovieListItem
  alias Bolognesa.Catalog.Application.Dto.MoviePage
  alias Bolognesa.Catalog.Application.Dto.MovieVersion
  alias Bolognesa.Catalog.Domain.Movie
  alias Bolognesa.Catalog.Domain.MovieVersion, as: DomainMovieVersion
  alias Bolognesa.Catalog.Infrastructure.Readers.EctoCatalogReader
  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Infrastructure.Persistence.MovieSchema

  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema

  test "groups physical versions and retains movies with missing files" do
    actor = %Actor{id: 1, role: :admin}

    library =
      Repo.insert!(
        LibrarySchema.changeset(%LibrarySchema{}, %{name: "Catalog", path: "/catalog"})
      )

    movie =
      Repo.insert!(
        movie_changeset(%{
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

      Bolognesa.IdentificationFixtures.insert_decision!(
        %{
          media_file_id: file.id,
          observed_revision: 1,
          token: Ecto.UUID.generate(),
          state: :automatic,
          origin: :automatic
        },
        [movie.id]
      )
    end

    assert {:error, :forbidden} = Catalog.list_movies(nil, "", 1)

    assert {:ok,
            %MoviePage{
              items: [%MovieListItem{id: id, version_count: 2, available_count: 1}],
              total: 1
            }} =
             Catalog.list_movies(actor, "Mi", 1)

    assert id == movie.id

    assert {:ok, {[{%Movie{id: ^id}, 2, 1}], 1}} = EctoCatalogReader.list_movies("Mi", 1)

    assert {:ok, {%Movie{id: ^id}, [version | _]}} =
             EctoCatalogReader.get_movie(id)

    assert version.__struct__ == DomainMovieVersion
    assert version.availability == :available

    assert {:ok, %MovieDetail{movie: %Movie{} = catalog_movie, versions: versions}} =
             Catalog.get_movie(actor, movie.id)

    assert catalog_movie.id == movie.id
    assert catalog_movie.title == "Mi pelicula"
    assert length(versions) == 2
    assert Enum.all?(versions, &match?(%MovieVersion{}, &1))
    assert {:ok, %MoviePage{items: [], total: 0}} = Catalog.list_movies(actor, "No existe", 1)
  end

  defp movie_changeset(attrs) do
    entry =
      Repo.insert!(
        CatalogEntrySchema.changeset(
          %CatalogEntrySchema{},
          %{kind: :movie, provider: :tmdb, resource_type: :movie, provider_id: attrs.provider_id}
        )
      )

    MovieSchema.changeset(%MovieSchema{id: entry.id}, Map.drop(attrs, [:provider, :provider_id]))
  end
end
