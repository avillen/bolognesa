defmodule BolognesaWeb.Movie.Index.LiveTest do
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Bolognesa.Identity
  alias Bolognesa.Infrastructure.Persistence.MovieSchema
  alias Bolognesa.Repo

  setup do
    {:ok, _} =
      Identity.install_admin(%{
        name: "Ada",
        email: "movies@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} = Identity.start_session("movies@example.com", "correct horse battery staple")
    %{token: token}
  end

  test "catalog shows search and empty state", %{conn: conn, token: token} do
    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/movies")
    render_async(view)
    assert has_element?(view, "#movies-list")
    assert has_element?(view, "#movie-search-form")
    assert has_element?(view, "#movies-empty")
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
    view |> form("#movie-search-form", search: %{query: "otra"}) |> render_submit()
    render_async(view)
    refute has_element?(view, "#movie-link-#{movie.id}")
    assert has_element?(view, "#movies-empty")
  end

  test "sidebar uses library names and types, including empty libraries", %{
    conn: conn,
    token: token
  } do
    movies = Bolognesa.SeriesFixtures.library(:movie)
    series = Bolognesa.SeriesFixtures.library(:series)
    Repo.update!(Ecto.Changeset.change(movies, name: "Family movies"))
    Repo.update!(Ecto.Changeset.change(series, name: "Documentaries"))

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
    series = Bolognesa.SeriesFixtures.library(:series)

    for id <- ["invalid", "9999999", "#{series.id}"] do
      assert {:error, {:live_redirect, %{to: "/libraries"}}} =
               live(init_test_session(conn, user_token: token), "/movies?library_id=#{id}")
    end
  end

  defp movie_changeset(attrs),
    do: MovieSchema.changeset(%MovieSchema{}, Map.put_new(attrs, :provider, :tmdb))
end
