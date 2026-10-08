defmodule BolognesaWeb.Movie.Review.LiveTest do
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Bolognesa.Identity
  alias Bolognesa.Repo

  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository.IdentificationSchema

  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoLibraryRepository.LibrarySchema
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository.MediaFileSchema

  test "review queue shows correction controls", %{conn: conn} do
    {:ok, _} =
      Identity.install_admin(%{
        name: "Ada",
        email: "review@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} = Identity.start_session("review@example.com", "correct horse battery staple")
    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/movies/review")
    render_async(view)
    assert has_element?(view, "#review-list")
    assert has_element?(view, "#correction-form")
  end

  test "administrator can mark a pending file unidentified", %{conn: conn} do
    {:ok, _} =
      Identity.install_admin(%{
        name: "Ada",
        email: "decision@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} = Identity.start_session("decision@example.com", "correct horse battery staple")

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
      IdentificationSchema.changeset(%IdentificationSchema{}, %{
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

    assert %{state: :manual_unidentified, origin: :manual} =
             Repo.get_by!(IdentificationSchema, media_file_id: file.id)
  end

  test "missing TMDb token has an actionable review state", %{conn: conn} do
    {:ok, _} =
      Identity.install_admin(%{
        name: "Ada",
        email: "missing-token@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} =
      Identity.start_session("missing-token@example.com", "correct horse battery staple")

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
      IdentificationSchema.changeset(%IdentificationSchema{}, %{
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
end
