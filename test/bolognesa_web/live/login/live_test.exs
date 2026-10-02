defmodule BolognesaWeb.Login.LiveTest do
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Bolognesa.Identity

  test "the login screen posts credentials through a browser form", %{conn: conn} do
    {:ok, _} =
      Identity.install_admin(%{
        name: "Ada",
        email: "ada@example.com",
        password: "correct horse battery staple"
      })

    {:ok, view, _html} = live(conn, ~p"/login")
    assert has_element?(view, "#login-form[action='/login'][method='post']")
    assert has_element?(view, "#login-email")
    assert has_element?(view, "#login-password")
    refute has_element?(view, "#home-screen")
  end

  test "login leads to setup until the first administrator exists", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/setup"}}} = live(conn, ~p"/login")
  end
end
