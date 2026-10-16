defmodule BolognesaWeb.Movie.Review.LiveTest do
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Bolognesa.Accounts
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.MovieIdentificationSchema
  alias Bolognesa.Repo

  test "review queue shows correction controls", %{conn: conn} do
    {:ok, _} =
      Accounts.install_admin(%{
        name: "Ada",
        email: "review@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} = Accounts.start_session("review@example.com", "correct horse battery staple")
    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/movies/review")
    render_async(view)
    assert has_element?(view, "#review-list")
    assert has_element?(view, "#correction-form")
  end

  test "administrator can mark a pending file unidentified", %{conn: conn} do
    {:ok, _} =
      Accounts.install_admin(%{
        name: "Ada",
        email: "decision@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} = Accounts.start_session("decision@example.com", "correct horse battery staple")

    library =
      Repo.insert!(
        LibrarySchema.changeset(%LibrarySchema{}, %{name: "Review", path: "/ui-review"})
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
      MovieIdentificationSchema.changeset(%MovieIdentificationSchema{}, %{
        media_file_id: file.id,
        observed_revision: 1,
        token: Ecto.UUID.generate(),
        state: :pending
      })
    )

    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/movies/review")
    render_async(view)
    assert has_element?(view, "#review-select-#{file.id}")
    view |> element("#review-select-#{file.id}") |> render_click()
    view |> element("#correction-unidentified") |> render_click()
    render_async(view)
    assert has_element?(view, "#review-feedback", "Corrección guardada")
    assert has_element?(view, "#review-select-#{file.id}")

    assert %{state: :manual_unidentified, origin: :manual} =
             Repo.get_by!(MovieIdentificationSchema, media_file_id: file.id)
  end

  test "missing TMDb token has an actionable review state", %{conn: conn} do
    {:ok, _} =
      Accounts.install_admin(%{
        name: "Ada",
        email: "missing-token@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} =
      Accounts.start_session("missing-token@example.com", "correct horse battery staple")

    library =
      Repo.insert!(
        LibrarySchema.changeset(%LibrarySchema{}, %{name: "No token", path: "/no-token"})
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
      MovieIdentificationSchema.changeset(%MovieIdentificationSchema{}, %{
        media_file_id: file.id,
        observed_revision: 1,
        token: Ecto.UUID.generate(),
        state: :failed,
        failure_reason: "not_configured"
      })
    )

    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/movies/review")
    render_async(view)
    assert has_element?(view, "#review-failure-#{file.id}", "TMDb sin configurar")
    view |> element("#review-select-#{file.id}") |> render_click()
    view |> form("#correction-form", correction: %{query: "Film"}) |> render_submit()
    render_async(view)
    assert has_element?(view, "#review-feedback", "TMDb sin configurar")
  end

  test "switching files clears the previous candidate choice", %{conn: conn} do
    {:ok, _} =
      Accounts.install_admin(%{
        name: "Ada",
        email: "switch@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} = Accounts.start_session("switch@example.com", "correct horse battery staple")

    library =
      Repo.insert!(LibrarySchema.changeset(%LibrarySchema{}, %{name: "Switch", path: "/switch"}))

    ids =
      for name <- ["A.mkv", "B.mkv"] do
        file =
          Repo.insert!(
            MediaFileSchema.changeset(%MediaFileSchema{}, %{
              library_id: library.id,
              relative_path: name,
              size_bytes: 1,
              modified_at: DateTime.utc_now(),
              last_seen_generation: Ecto.UUID.generate()
            })
          )

        Repo.insert!(
          MovieIdentificationSchema.changeset(%MovieIdentificationSchema{}, %{
            media_file_id: file.id,
            observed_revision: 1,
            token: Ecto.UUID.generate(),
            state: :pending
          })
        )

        file.id
      end

    [a_id, b_id] = ids
    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/movies/review")
    render_async(view)
    view |> element("#review-select-#{a_id}") |> render_click()
    render_click(view, "choose_candidate", %{"tmdb_id" => "123"})
    assert has_element?(view, "#correction-tmdb-id[value='123']")
    view |> element("#review-select-#{b_id}") |> render_click()
    assert has_element?(view, "#correction-tmdb-id[value='']")
  end
end
