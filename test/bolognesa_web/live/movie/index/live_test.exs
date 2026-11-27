defmodule BolognesaWeb.Movie.Index.LiveTest do
  alias Bolognesa.SeriesFixtures
  alias Ecto.Changeset
  alias Phoenix.LiveViewTest
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Bolognesa.RepoReads, only: [watch_reads: 2]

  alias Bolognesa.Accounts
  alias Bolognesa.Infrastructure.Persistence.MovieSchema
  alias Bolognesa.Infrastructure.Persistence.MovieWatchedSchema
  alias Bolognesa.Infrastructure.Persistence.UserSchema
  alias Bolognesa.MovieIdentificationFixtures

  alias Bolognesa.Movies.Infrastructure.Repositories.EctoWatchedMoviesRepository,
    as: WatchedRepository

  alias Bolognesa.Repo
  alias Ecto.UUID

  setup do
    {:ok, _} =
      Accounts.install_admin(%{
        name: "Ada",
        email: "movies@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} = Accounts.start_session("movies@example.com", "correct horse battery staple")
    %{token: token}
  end

  test "catalog shows search and empty state", %{conn: conn, token: token} do
    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/movies")
    render_async(view)
    assert has_element?(view, "#movies-list")
    assert has_element?(view, "#movie-search-form")
    assert has_element?(view, "#movies-empty", "No hay películas en esta biblioteca")
    refute has_element?(view, "#movies-clear-search")
    refute has_element?(view, "#movies-count")
    assert has_element?(view, "#movies-screen[phx-hook='BrowsePosition'][data-loading='false']")

    assert has_element?(
             view,
             "#movies-library-options #movies-review-link[href='/movies/review']"
           )
  end

  test "search without matches offers a reset", %{conn: conn, token: token} do
    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/movies?query=Nada")
    render_async(view)
    assert has_element?(view, "#movies-empty", "No hay películas que coincidan")
    view |> element("#movies-clear-search") |> render_click()
    assert_patch(view, "/movies")
    render_async(view)
    refute has_element?(view, "#movies-clear-search")
  end

  test "a failed load offers a retry", %{conn: conn, token: token} do
    query = String.duplicate("a", 257)
    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/movies?query=#{query}")
    render_async(view)
    assert has_element?(view, "#movies-error", "No se pudo cargar el catálogo.")

    assert has_element?(
             view,
             "#movies-error a[href='/movies?page=1&query=#{query}']",
             "Reintentar"
           )

    refute has_element?(view, "#movies-empty")
  end

  test "anonymous visitor is redirected", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/movies")
  end

  test "search keeps matching catalog cards", %{conn: conn, token: token} do
    movie =
      Repo.insert!(
        movie_changeset(%{
          provider: :tmdb,
          provider_id: 200,
          title: "Luz de invierno",
          poster_path: "/poster.jpg"
        })
      )

    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/movies")
    render_async(view)
    assert has_element?(view, "#movie-link-#{movie.id}")
    assert has_element?(view, "#movie-poster-#{movie.id}[phx-hook='ImageFallback']")
    view |> form("#movie-search-form", search: %{query: "otra"}) |> render_change()
    render_async(view)
    refute has_element?(view, "#movie-link-#{movie.id}")
    assert has_element?(view, "#movies-empty")

    view |> form("#movie-search-form", search: %{query: "L"}) |> render_change()
    render_async(view)
    assert has_element?(view, "#movie-link-#{movie.id}")
    assert has_element?(view, "#movies-count", "1 película")

    view |> form("#movie-search-form", search: %{query: ""}) |> render_change()
    render_async(view)
    assert has_element?(view, "#movie-link-#{movie.id}")
  end

  test "watched movies show a marker over the poster", %{conn: conn, token: token} do
    watched = Repo.insert!(movie_changeset(%{provider: :tmdb, provider_id: 201, title: "Vista"}))
    unwatched = Repo.insert!(movie_changeset(%{provider: :tmdb, provider_id: 202, title: "Otra"}))
    [user] = Repo.all(UserSchema)

    Repo.insert!(%MovieWatchedSchema{
      user_id: user.id,
      movie_id: watched.id,
      last_watched_at: DateTime.utc_now()
    })

    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/movies")
    render_async(view)
    assert has_element?(view, "#movie-link-#{watched.id} #movie-watched-#{watched.id}", "Visto")
    assert has_element?(view, "#movie-link-#{unwatched.id}")
    refute has_element?(view, "#movie-watched-#{unwatched.id}")
  end

  test "sidebar uses library names and types, including empty libraries", %{
    conn: conn,
    token: token
  } do
    movies = SeriesFixtures.library(:movie)
    series = SeriesFixtures.library(:series)
    Repo.update!(Changeset.change(movies, name: "Family movies"))
    Repo.update!(Changeset.change(series, name: "Documentaries"))

    {:ok, view, _} =
      live(init_test_session(conn, user_token: token), "/movies?library_id=#{movies.id}")

    render_async(view)
    assert has_element?(view, "#nav-library-#{movies.id}[aria-current='page']", "Family movies")
    assert has_element?(view, "#nav-library-#{movies.id} .hero-film")

    assert has_element?(
             view,
             "#nav-library-#{series.id}[href='/series?library_id=#{series.id}']",
             "Documentaries"
           )

    assert has_element?(view, "#nav-library-#{series.id} .hero-tv")
    refute has_element?(view, "nav a[href='/movies']")
    refute has_element?(view, "nav a[href='/series']")
    assert has_element?(view, "h1", "Family movies")
    assert has_element?(view, "#movies-empty")
    view |> form("#movie-search-form", search: %{query: "test"}) |> render_submit()
    assert_patch(view, "/movies?library_id=#{movies.id}&query=test")
  end

  test "invalid or wrong-type library never opens the global movie catalog", %{
    conn: conn,
    token: token
  } do
    series = SeriesFixtures.library(:series)

    for id <- ["invalid", "9999999", "#{series.id}"] do
      assert {:error, {:live_redirect, %{to: "/libraries"}}} =
               live(init_test_session(conn, user_token: token), "/movies?library_id=#{id}")
    end
  end

  test "leads with recently watched movies, hidden while searching", %{conn: conn, token: token} do
    conn = init_test_session(conn, user_token: token)
    {:ok, view, _} = live(conn, ~p"/movies")
    render_async(view)
    refute has_element?(view, "#movies-recent-shelf")

    user = Repo.get_by!(UserSchema, email: "movies@example.com")

    [older, newer] =
      for {id, days_ago} <- [{300, 1}, {301, 0}] do
        movie =
          Repo.insert!(
            movie_changeset(%{provider_id: id, title: "Vista #{id}", overview: "Sinopsis #{id}"})
          )

        :ok =
          WatchedRepository.upsert(
            user.id,
            movie.id,
            DateTime.add(DateTime.utc_now(), -days_ago, :day)
          )

        movie
      end

    {:ok, view, _} = live(conn, ~p"/movies")
    render_async(view)
    assert has_element?(view, "#recent-movie-#{newer.id}.is-lead", "Sinopsis 301")
    refute has_element?(view, "#recent-movie-#{older.id}.is-lead")
    refute has_element?(view, "#recent-movie-#{older.id}", "Sinopsis 300")

    assert has_element?(
             view,
             "#recent-movie-open-#{older.id}[href='/movies/#{older.id}']",
             "Ver ficha"
           )

    assert has_element?(view, "#movies-list #movie-link-#{newer.id}")

    {:ok, view, _} = live(conn, ~p"/movies?query=Vista")
    render_async(view)
    refute has_element?(view, "#movies-recent-shelf")
  end

  test "a new search cancels the superseded catalog read", %{conn: conn, token: token} do
    movie = Repo.insert!(movie_changeset(%{provider_id: 500, title: "Cancelable"}))
    watch_reads(fn _query, params -> "Cancel" in params end, fn _params -> true end)
    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/movies?query=Cancel")
    assert_receive {:read, reader, _params}, 5_000
    monitor = Process.monitor(reader)
    render_patch(view, ~p"/movies?query=Cancelable")
    assert_receive {:DOWN, ^monitor, :process, ^reader, {:shutdown, :cancel}}, 5_000
    render_async(view)
    assert has_element?(view, "#movie-link-#{movie.id}")
  end

  test "the recent shelf survives search and paging and clears on a library switch", %{
    conn: conn,
    token: token
  } do
    library = SeriesFixtures.library(:movie)
    other = SeriesFixtures.library(:movie)
    movie = library_movie(library, 400)
    user = Repo.get_by!(UserSchema, email: "movies@example.com")
    :ok = WatchedRepository.upsert(user.id, movie.id, DateTime.utc_now())
    watch_reads(&recent_read?/2, &(other.id in &1))

    {:ok, view, _} =
      live(init_test_session(conn, user_token: token), "/movies?library_id=#{library.id}")

    render_async(view)
    assert_received {:read, _reader, params}
    assert library.id in params
    tile = "#recent-movie-#{movie.id}"
    assert has_element?(view, tile)

    render_patch(view, "/movies?library_id=#{library.id}&query=Vista")
    render_patch(view, "/movies?library_id=#{library.id}&page=2")
    render_patch(view, "/movies?library_id=#{library.id}")
    assert has_element?(view, tile)
    render_async(view)
    refute_received {:read, _reader, _params}

    render_patch(view, "/movies?library_id=#{other.id}")
    assert_receive {:read, reader, params}, 5_000
    assert other.id in params
    refute has_element?(view, tile)
    send(reader, :continue)
    render_async(view)
    refute has_element?(view, "#movies-recent-shelf")
  end

  defp library_movie(library, provider_id) do
    movie =
      Repo.insert!(movie_changeset(%{provider_id: provider_id, title: "Vista #{provider_id}"}))

    file = SeriesFixtures.file(library.id, "Vista #{provider_id}.mkv")

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

    movie
  end

  defp recent_read?(query, _params),
    do: query =~ ~r/FROM "movies_watched" AS \w+ INNER JOIN "movies"/

  defp movie_changeset(attrs),
    do: MovieSchema.changeset(%MovieSchema{}, Map.put_new(attrs, :provider, :tmdb))
end
