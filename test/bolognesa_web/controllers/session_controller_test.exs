defmodule BolognesaWeb.SessionControllerTest do
  use BolognesaWeb.ConnCase, async: false

  alias Bolognesa.Accounts

  @password "correct horse battery staple"

  setup do
    {:ok, actor} =
      Accounts.install_admin(%{name: "Ada", email: "ada@example.com", password: @password})

    %{actor: actor}
  end

  test "valid credentials create a cookie session and reach the protected page", %{conn: conn} do
    conn =
      post(conn, ~p"/login", %{
        "login" => %{"email" => "ada@example.com", "password" => @password}
      })

    assert redirected_to(conn) == ~p"/"
    assert token = get_session(conn, :user_token)
    assert {:ok, _actor} = Accounts.fetch_authenticated_user(token)
    assert conn |> recycle() |> get(~p"/") |> html_response(200)
  end

  test "invalid credentials return generic feedback without a session", %{conn: conn} do
    conn =
      post(conn, ~p"/login", %{"login" => %{"email" => "ada@example.com", "password" => "wrong"}})

    assert redirected_to(conn) == ~p"/login"
    assert get_session(conn, :user_token) == nil
    refute get_resp_header(conn, "location") |> Enum.join() =~ "wrong"
  end

  test "logout revokes the current cookie and an old cookie cannot be replayed", %{conn: conn} do
    login =
      post(conn, ~p"/login", %{
        "login" => %{"email" => "ada@example.com", "password" => @password}
      })

    token = get_session(login, :user_token)
    logout = login |> recycle() |> delete(~p"/logout")
    assert redirected_to(logout) == ~p"/login"
    assert {:error, :unauthenticated} = Accounts.fetch_authenticated_user(token)
    assert get_session(logout, :user_token) == nil
    assert redirected_to(login |> recycle() |> get(~p"/")) == ~p"/login"
  end
end
