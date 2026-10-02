defmodule BolognesaWeb.Setup.LiveTest do
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Bolognesa.Identity

  @valid %{
    name: "Ada",
    email: "ada@example.com",
    password: "correct horse battery staple",
    password_confirmation: "correct horse battery staple"
  }

  test "an empty installation offers the administrator form", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/setup")
    assert has_element?(view, "#setup-form")
    assert has_element?(view, "#setup-name")
    assert has_element?(view, "#setup-email")
    assert has_element?(view, "#setup-password")
    assert has_element?(view, "#setup-password-confirmation")
  end

  test "invalid input stays on setup and does not create an administrator", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/setup")

    view
    |> form("#setup-form",
      admin: %{name: "", email: "invalid", password: "short", password_confirmation: "different"}
    )
    |> render_change()

    assert has_element?(view, "#setup-form")
    assert {:ok, :open} = Identity.setup_status()
  end

  test "valid setup creates the administrator and closes setup", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/setup")
    view |> form("#setup-form", admin: @valid) |> render_submit()
    assert_redirect(view, "/login")
    assert {:ok, :closed} = Identity.setup_status()
    assert {:error, {:redirect, %{to: "/login"}}} = live(build_conn(), ~p"/setup")
  end

  test "a stale form cannot create a second administrator", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/setup")

    assert {:ok, _} =
             Identity.install_admin(%{
               name: "First",
               email: "first@example.com",
               password: "correct horse battery staple"
             })

    view |> form("#setup-form", admin: @valid) |> render_submit()
    assert_redirect(view, "/login")

    assert {:error, :invalid_credentials} =
             Identity.start_session("ada@example.com", "correct horse battery staple")
  end

  test "a stale form redirects even when its submitted fields are invalid", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/setup")

    assert {:ok, _} =
             Identity.install_admin(%{
               name: "First",
               email: "first@example.com",
               password: "correct horse battery staple"
             })

    view
    |> form("#setup-form",
      admin: %{name: "", email: "bad", password: "short", password_confirmation: "short"}
    )
    |> render_submit()

    assert_redirect(view, "/login")
  end
end
