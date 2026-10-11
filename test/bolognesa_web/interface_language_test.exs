defmodule BolognesaWeb.InterfaceLanguageTest do
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Bolognesa.Identity
  alias Bolognesa.Infrastructure.Persistence.IdentificationSchema
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Repo

  setup %{conn: conn} do
    {:ok, actor} =
      Identity.install_admin(%{
        name: "Ada",
        email: "ada@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} = Identity.start_session("ada@example.com", "correct horse battery staple")
    %{conn: init_test_session(conn, user_token: token), actor: actor, token: token}
  end

  test "English reaches public forms, navigation and asynchronous catalog states", %{conn: conn} do
    conn = put_req_header(conn, "accept-language", "en-US")
    {:ok, login, _} = live(conn, "/login")
    assert has_element?(login, "label[for=login-email]", "Email")
    {:ok, movies, _} = live(conn, "/movies")
    render_async(movies)
    assert has_element?(movies, "#movies-empty", "No movies")
    {:ok, series, _} = live(conn, "/series")
    render_async(series)
    assert has_element?(series, "#series-empty", "No series")
    {:ok, review, _} = live(conn, "/movies/review")
    render_async(review)
    assert has_element?(review, "h1", "Review")
    {:ok, libraries, _} = live(conn, "/libraries")
    libraries |> form("#library-form", library: %{name: "", path: ""}) |> render_submit()
    assert has_element?(libraries, "#library-form", "can't be blank")
  end

  test "live processes remain isolated and new mounts recover account choice", %{
    conn: conn,
    actor: actor,
    token: token
  } do
    {:ok, english, _} = live(put_req_header(conn, "accept-language", "en"), "/settings")
    {:ok, spanish, _} = live(put_req_header(conn, "accept-language", "es"), "/settings")
    assert has_element?(english, "#save-locale", "Save")
    assert has_element?(spanish, "#save-locale", "Guardar")
    render_submit(english, "save", %{"preferences" => %{"locale" => "fr"}})
    render_submit(spanish, "save", %{"preferences" => %{"locale" => "fr"}})
    assert has_element?(english, "#locale-form", "is invalid")
    assert has_element?(spanish, "#locale-form", "no es válido")
    assert {:ok, _} = Identity.update_locale(actor, "en")
    assert has_element?(spanish, "#save-locale", "Guardar")
    {:ok, reopened, _} = live(init_test_session(build_conn(), user_token: token), "/settings")
    assert has_element?(reopened, "#save-locale", "Save")
  end

  test "LiveView navigation retains the negotiated locale", %{conn: conn} do
    conn = put_req_header(conn, "accept-language", "en")
    {:ok, view, _} = live(conn, "/settings")
    result = view |> element("a[href='/movies']") |> render_click()
    {:ok, movies, _} = follow_redirect(result, conn, "/movies")
    render_async(movies)
    assert has_element?(movies, "#movies-empty", "No movies")
    result = movies |> element("#nav-settings") |> render_click()
    {:ok, settings, _} = follow_redirect(result, conn, "/settings")
    assert has_element?(settings, "#save-locale", "Save")
  end

  for {kind, path, selector} <- [
        {:movie, "/movies/review", "#review-list"},
        {:series, "/series/review", "#series-review-list"}
      ] do
    test "pending #{kind} review rows use English", %{conn: conn} do
      library =
        Repo.insert!(
          LibrarySchema.changeset(%LibrarySchema{}, %{
            name: "Language",
            path: "/language-#{unquote(kind)}",
            content_type: unquote(kind)
          })
        )

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
          observed_revision: 1,
          token: Ecto.UUID.generate(),
          state: :pending
        })
      )

      {:ok, view, _} = live(put_req_header(conn, "accept-language", "en"), unquote(path))
      render_async(view)
      assert has_element?(view, unquote(selector), "Pending")
    end
  end

  test "playback browser errors are translated in the page process" do
    rendered =
      Gettext.with_locale(BolognesaWeb.Gettext, "en", fn ->
        render_component(&BolognesaWeb.Player.player/1,
          prefix: "movie",
          kind: :movie,
          entry_id: 1,
          selected_file_id: 1,
          compatible_ready?: false,
          compatible_paused?: false,
          compatible_autoplay?: false
        )
      end)

    assert rendered
           |> LazyHTML.from_fragment()
           |> LazyHTML.filter("#movie-player")
           |> LazyHTML.text() =~ "Playing version"
  end
end
