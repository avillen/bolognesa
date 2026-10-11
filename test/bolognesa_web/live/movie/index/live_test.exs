defmodule BolognesaWeb.Movie.Index.LiveTest do
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Bolognesa.Identity
  alias Bolognesa.Persistence.MovieSchema
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
        MovieSchema.changeset(%MovieSchema{}, %{
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
end
