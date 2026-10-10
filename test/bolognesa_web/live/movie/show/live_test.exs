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

  test "selects available versions and clears an old playback error", %{conn: conn} do
    {:ok, _} =
      Identity.install_admin(%{
        name: "Ada",
        email: "play-show@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} =
      Identity.start_session("play-show@example.com", "correct horse battery staple")

    movie =
      Repo.insert!(
        MovieSchema.changeset(%MovieSchema{}, %{
          provider: :tmdb,
          provider_id: 1001,
          title: "Mi pelicula"
        })
      )

    library =
      Repo.insert!(LibrarySchema.changeset(%LibrarySchema{}, %{name: "Play", path: "/play"}))

    first = insert_version(library.id, movie.id, "first.mp4", :available)
    second = insert_version(library.id, movie.id, "second.mp4", :available)
    missing = insert_version(library.id, movie.id, "missing.mp4", :missing)

    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/movies/#{movie.id}")
    render_async(view)

    assert has_element?(view, "#movie-play-#{first.id}")
    assert has_element?(view, "#movie-play-#{second.id}")
    refute has_element?(view, "#movie-play-#{missing.id}")

    render_click(element(view, "#movie-play-#{first.id}"))
    assert has_element?(view, "#movie-player video[src='/movies/#{movie.id}/media/#{first.id}']")
    render_hook(view, "playback_error", %{"file_id" => Integer.to_string(first.id)})
    assert has_element?(view, "#movie-playback-error[role='alert']")

    render_click(element(view, "#movie-play-#{second.id}"))
    assert has_element?(view, "#movie-player video[src='/movies/#{movie.id}/media/#{second.id}']")
    refute has_element?(view, "#movie-video-#{first.id}")
    refute has_element?(view, "#movie-playback-error")
    render_hook(view, "playback_error", %{"file_id" => Integer.to_string(first.id)})
    refute has_element?(view, "#movie-playback-error")
  end

  defp insert_version(library_id, movie_id, path, availability) do
    file =
      Repo.insert!(
        MediaFileSchema.changeset(%MediaFileSchema{}, %{
          library_id: library_id,
          relative_path: path,
          size_bytes: 1,
          modified_at: DateTime.utc_now(),
          availability: availability,
          last_seen_generation: Ecto.UUID.generate()
        })
      )

    Repo.insert!(
      IdentificationSchema.changeset(%IdentificationSchema{}, %{
        media_file_id: file.id,
        movie_id: movie_id,
        observed_revision: 1,
        token: Ecto.UUID.generate(),
        state: :automatic,
        origin: :automatic
      })
    )

    file
  end
end
