defmodule Bolognesa.Movies.CatalogQueriesTest do
  alias Bolognesa.MovieIdentificationFixtures
  alias Bolognesa.SeriesFixtures
  alias Ecto.Changeset
  alias Ecto.UUID
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.MovieSchema
  alias Bolognesa.Movies
  alias Bolognesa.Movies.Application.UseCases.GetMovie.Response, as: MovieDetail
  alias Bolognesa.Movies.Application.UseCases.GetMovie.Version, as: MovieVersion
  alias Bolognesa.Movies.Application.UseCases.ListMovies.Item, as: MovieListItem
  alias Bolognesa.Movies.Application.UseCases.ListMovies.Response, as: MoviePage
  alias Bolognesa.Movies.Domain.ReadModels.Movie
  alias Bolognesa.Movies.Domain.ReadModels.MovieVersion, as: DomainMovieVersion
  alias Bolognesa.Movies.Infrastructure.Readers.EctoMoviesReader

  test "groups physical versions and retains movies with missing files" do
    actor = %AuthenticatedUser{id: 1, role: :admin}

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
            last_seen_generation: UUID.generate()
          })
        )

      MovieIdentificationFixtures.insert_decision!(
        %{
          media_file_id: file.id,
          observed_revision: 1,
          token: UUID.generate(),
          state: :automatic,
          origin: :automatic
        },
        movie.id
      )
    end

    assert {:error, :forbidden} = Movies.list_movies(nil, "", 1)

    assert {:ok,
            %MoviePage{
              items: [%MovieListItem{id: id, version_count: 2, available_count: 1}],
              total: 1
            }} =
             Movies.list_movies(actor, "Mi", 1)

    assert id == movie.id

    assert {:ok, {[{%Movie{id: ^id}, 2, 1, nil}], 1}} =
             EctoMoviesReader.list_movies(actor.id, "Mi", 1, nil)

    assert {:ok, {%Movie{id: ^id}, [version | _]}} =
             EctoMoviesReader.get_movie(id)

    assert version.__struct__ == DomainMovieVersion
    assert version.availability == :available

    assert {:ok, %MovieDetail{movie: %Movie{} = catalog_movie, versions: versions}} =
             Movies.get_movie(actor, movie.id)

    assert catalog_movie.id == movie.id
    assert catalog_movie.title == "Mi pelicula"
    assert length(versions) == 2
    assert Enum.all?(versions, &match?(%MovieVersion{}, &1))
    assert {:ok, %MoviePage{items: [], total: 0}} = Movies.list_movies(actor, "No existe", 1)
  end

  test "library catalogs isolate titles, counts and pagination while retaining missing files" do
    actor = %AuthenticatedUser{id: 1, role: :admin}
    first = SeriesFixtures.library(:movie)
    second = SeriesFixtures.library(:movie)
    shared = Repo.insert!(movie_changeset(%{provider_id: 901, title: "Shared"}))
    other = Repo.insert!(movie_changeset(%{provider_id: 902, title: "Other"}))

    for {library, movie, availability} <- [
          {first, shared, :missing},
          {second, shared, :available},
          {second, other, :available}
        ] do
      file = SeriesFixtures.file(library.id, "#{movie.id}.mkv")
      Repo.update!(Changeset.change(file, availability: availability))

      MovieIdentificationFixtures.insert_decision!(
        %{
          media_file_id: file.id,
          observed_revision: 1,
          token: UUID.generate(),
          state: :manual,
          origin: :manual
        },
        movie.id
      )
    end

    assert {:ok, %{total: 1, items: [item]}} = Movies.list_movies(actor, "", 1, first.id)
    assert item.id == shared.id
    assert item.version_count == 1
    assert item.available_count == 0
    assert {:ok, %{total: 1, items: []}} = Movies.list_movies(actor, "", 2, first.id)
    assert {:ok, %{total: 0, items: []}} = Movies.list_movies(actor, "Other", 1, first.id)
    assert {:ok, %{total: 2}} = Movies.list_movies(actor, "", 1, second.id)
    assert {:error, :forbidden} = Movies.list_movies(nil, "", 1, first.id)
    assert {:error, :invalid_query} = Movies.list_movies(actor, "", 1, -1)
  end

  test "pagination selects title/id members before counting their scoped versions" do
    actor = %AuthenticatedUser{id: 1, role: :admin}
    first = SeriesFixtures.library(:movie)
    second = SeriesFixtures.library(:movie)

    movies =
      for index <- 1..25 do
        movie = Repo.insert!(movie_changeset(%{provider_id: 1000 + index, title: "Paged"}))
        insert_version(first.id, movie.id, index)
        movie
      end

    last = List.last(movies)
    missing = Repo.get!(MediaFileSchema, insert_version(first.id, last.id, 26).media_file_id)
    Repo.update!(Changeset.change(missing, availability: :missing))
    insert_version(second.id, last.id, 27)
    ids = Enum.map(movies, & &1.id)

    assert {:ok, %{total: 25, items: items}} = Movies.list_movies(actor, "Paged", 1)
    assert Enum.map(items, & &1.id) == Enum.take(ids, 24)
    assert Enum.all?(items, &(&1.version_count == 1 and &1.available_count == 1))

    for {library_id, total, versions, available} <- [
          {nil, 25, 3, 2},
          {first.id, 25, 2, 1}
        ] do
      assert {:ok, %{total: ^total, items: [item]}} =
               Movies.list_movies(actor, "Paged", 2, library_id)

      assert {item.id, item.version_count, item.available_count} ==
               {last.id, versions, available}
    end

    assert {:ok, %{total: 1, items: [item]}} = Movies.list_movies(actor, "Paged", 1, second.id)
    assert {item.id, item.version_count, item.available_count} == {last.id, 1, 1}
    assert {:ok, %{total: 1, items: []}} = Movies.list_movies(actor, "Paged", 2, second.id)
  end

  test "movie details reject more than one hundred versions without returning a partial list" do
    actor = %AuthenticatedUser{id: 1, role: :admin}
    library = SeriesFixtures.library(:movie)
    movie = Repo.insert!(movie_changeset(%{provider_id: 903, title: "Many versions"}))

    for index <- 1..100 do
      insert_version(library.id, movie.id, index)
    end

    assert {:ok, %{versions: versions}} = Movies.get_movie(actor, movie.id)
    assert length(versions) == 100
    assert Enum.map(versions, & &1.id) == Enum.sort(Enum.map(versions, & &1.id))

    insert_version(library.id, movie.id, 101)
    assert {:error, :too_many_versions} = Movies.get_movie(actor, movie.id)
  end

  defp insert_version(library_id, movie_id, index) do
    file = SeriesFixtures.file(library_id, "version-#{index}.mkv")

    MovieIdentificationFixtures.insert_decision!(
      %{
        media_file_id: file.id,
        observed_revision: 1,
        token: UUID.generate(),
        state: :automatic,
        origin: :automatic
      },
      movie_id
    )
  end

  defp movie_changeset(attrs),
    do: MovieSchema.changeset(%MovieSchema{}, Map.put_new(attrs, :provider, :tmdb))
end
