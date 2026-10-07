defmodule BolognesaWeb.Movie.Show.LiveTest do
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Bolognesa.Identity
  alias Bolognesa.Catalog.Infrastructure.Persistence.EctoMovieRepository.MovieSchema
  alias Bolognesa.Repo

  test "shows movie details and versions container", %{conn: conn} do
    {:ok, _} =
      Identity.install_admin(%{
        name: "Ada",
        email: "show@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} = Identity.start_session("show@example.com", "correct horse battery staple")

    movie =
      Repo.insert!(
        MovieSchema.changeset(%MovieSchema{}, %{
          provider: :tmdb,
          provider_id: 999,
          title: "Mi pelicula"
        })
      )

    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/movies/#{movie.id}")
    render_async(view)
    assert has_element?(view, "#movie-versions")
    assert has_element?(view, "#movie-title", "Mi pelicula")
  end
end
