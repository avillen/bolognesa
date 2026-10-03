defmodule BolognesaWeb.Home.LiveTest do
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Bolognesa.Identity

  setup do
    {:ok, _} =
      Identity.install_admin(%{
        name: "Ada",
        email: "ada@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} = Identity.start_session("ada@example.com", "correct horse battery staple")
    %{token: token}
  end

  test "a verified administrator sees their identity and a logout form", %{
    conn: conn,
    token: token
  } do
    conn = init_test_session(conn, user_token: token)
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#home-screen")
    assert has_element?(view, "#home-welcome", "Ada")
    assert has_element?(view, "#home-libraries-link[href='/libraries']")
    assert has_element?(view, "#logout-button")
    assert has_element?(view, "#logout-form[action='/logout']")
    assert has_element?(view, "#logout-form input[name='_method'][value='delete']")
    assert has_element?(view, "#logout-form input[name='_csrf_token']")
  end

  test "an anonymous visitor cannot mount Inicio", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/")
  end

  test "a revoked token cannot mount Inicio", %{conn: conn, token: token} do
    assert :ok = Identity.end_session(token)
    conn = init_test_session(conn, user_token: token)
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/")
  end
end
