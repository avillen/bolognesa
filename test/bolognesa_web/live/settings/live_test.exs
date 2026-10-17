defmodule BolognesaWeb.Settings.LiveTest do
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Bolognesa.Accounts

  @password "correct horse battery staple"
  setup %{conn: conn} do
    {:ok, actor} =
      Accounts.install_admin(%{name: "Ada", email: "ada@example.com", password: @password})

    {:ok, token} = Accounts.start_session("ada@example.com", @password)
    %{conn: init_test_session(conn, user_token: token), actor: actor, token: token}
  end

  test "settings are protected" do
    assert redirected_to(get(build_conn(), "/settings")) == "/login"
  end

  test "saving reloads and applies the account locale", %{conn: conn, token: token} do
    conn = put_req_header(conn, "accept-language", "es")
    {:ok, view, _} = live(conn, "/settings")
    assert has_element?(view, "#nav-settings[aria-current=page]")
    view |> form("#locale-form", preferences: %{locale: "en"}) |> render_submit()
    assert_redirect(view, "/settings")
    assert {:ok, %{locale: "en"}} = Accounts.fetch_authenticated_user(token)
    conn = get(init_test_session(build_conn(), user_token: token), "/settings")

    assert conn
           |> html_response(200)
           |> LazyHTML.from_document()
           |> LazyHTML.filter("html[lang=en]")
           |> Enum.any?()

    {:ok, view, _} = live(recycle(conn), "/settings")
    assert has_element?(view, "#save-locale", "Save")
    view |> form("#locale-form", preferences: %{locale: ""}) |> render_submit()
    assert_redirect(view, "/settings")
    assert {:ok, %{locale: nil}} = Accounts.fetch_authenticated_user(token)
  end

  test "invalid and manipulated parameters never modify identity", %{conn: conn, token: token} do
    {:ok, view, _} = live(conn, "/settings")

    render_submit(view, "save", %{
      "preferences" => %{"locale" => "fr", "user_id" => "999", "role" => "member"}
    })

    assert has_element?(view, "#locale-form")
    assert {:ok, %{locale: nil, role: :admin}} = Accounts.fetch_authenticated_user(token)
  end
end
