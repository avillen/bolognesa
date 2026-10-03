defmodule BolognesaWeb.Library.Index.LiveTest do
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
    root = Application.fetch_env!(:bolognesa, :library_roots) |> hd()
    path = Path.join(root, "web-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    %{token: token, path: path}
  end

  test "administrator adds a source and sees it after reconnecting", %{
    conn: conn,
    token: token,
    path: path
  } do
    conn = init_test_session(conn, user_token: token)
    {:ok, view, _} = live(conn, ~p"/libraries")
    assert has_element?(view, "#library-form")
    assert has_element?(view, "#libraries-empty")
    view |> form("#library-form", library: %{name: "Películas", path: path}) |> render_submit()
    assert has_element?(view, "#library-list [data-library-name='Películas']")
    {:ok, reopened, _} = live(conn, ~p"/libraries")
    assert has_element?(reopened, "#library-list [data-library-name='Películas']")

    {:ok, new_token} = Identity.start_session("ada@example.com", "correct horse battery staple")
    new_conn = Phoenix.ConnTest.build_conn() |> init_test_session(user_token: new_token)
    {:ok, new_session, _} = live(new_conn, ~p"/libraries")
    assert has_element?(new_session, "#library-list [data-library-name='Películas']")
  end

  test "duplicate source keeps the form and shows feedback", %{
    conn: conn,
    token: token,
    path: path
  } do
    conn = init_test_session(conn, user_token: token)
    {:ok, view, _} = live(conn, ~p"/libraries")
    view |> form("#library-form", library: %{name: "One", path: path}) |> render_submit()
    view |> form("#library-form", library: %{name: "Two", path: path}) |> render_submit()
    assert has_element?(view, "#library-error")
    assert has_element?(view, "#library-list [data-library-name='One']")
  end

  test "anonymous visitors cannot open libraries", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/libraries")
  end
end
