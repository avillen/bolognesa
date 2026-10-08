defmodule BolognesaWeb.Movie.Show.LiveTest do
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Bolognesa.Identity
  alias Bolognesa.Catalog.Infrastructure.Persistence.EctoMovieRepository.MovieSchema
  alias Bolognesa.Repo

  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository.IdentificationSchema

  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoLibraryRepository.LibrarySchema
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository.MediaFileSchema

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

  test "each confirmed version can open manual correction", %{conn: conn} do
    {:ok, _} =
      Identity.install_admin(%{
        name: "Ada",
        email: "correct-show@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} =
      Identity.start_session("correct-show@example.com", "correct horse battery staple")

    movie =
      Repo.insert!(
        MovieSchema.changeset(%MovieSchema{}, %{
          provider: :tmdb,
          provider_id: 1000,
          title: "Mi pelicula"
        })
      )

    library =
      Repo.insert!(LibrarySchema.changeset(%LibrarySchema{}, %{name: "Show", path: "/show"}))

    file =
      Repo.insert!(
        MediaFileSchema.changeset(%MediaFileSchema{}, %{
          library_id: library.id,
          relative_path: "Film.mkv",
          size_bytes: 1,
          modified_at: DateTime.utc_now(),
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

    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/movies/#{movie.id}")
    render_async(view)

    assert has_element?(
             view,
             "#movie-correct-#{file.id}[href='/movies/review?file_id=#{file.id}']"
           )
  end
end
