defmodule BolognesaWeb.About.LiveTest do
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Bolognesa.Accounts

  test "authenticated about page attributes TMDb", %{conn: conn} do
    {:ok, _} =
      Accounts.install_admin(%{
        name: "Ada",
        email: "about@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} = Accounts.start_session("about@example.com", "correct horse battery staple")
    {:ok, view, _} = live(init_test_session(conn, user_token: token), ~p"/about")
    assert has_element?(view, "#tmdb-attribution")
    assert has_element?(view, "#tmdb-attribution img[alt]")
    assert has_element?(view, "#tmdb-attribution a[href='https://www.themoviedb.org']")
  end

  test "anonymous visitor cannot open about", %{conn: conn} do
    {:ok, _} =
      Accounts.install_admin(%{
        name: "Ada",
        email: "anonymous-about@example.com",
        password: "correct horse battery staple"
      })

    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/about")
  end
end
