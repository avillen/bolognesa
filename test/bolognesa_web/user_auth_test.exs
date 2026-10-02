defmodule BolognesaWeb.UserAuthTest do
  use BolognesaWeb.ConnCase, async: false

  alias Bolognesa.Identity
  alias BolognesaWeb.UserAuth

  test "an empty installation redirects anonymous visitors to setup", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/")) == "/setup"
  end

  test "an installed site redirects anonymous visitors to login", %{conn: conn} do
    {:ok, _} =
      Identity.install_admin(%{
        name: "Ada",
        email: "ada@example.com",
        password: "correct horse battery staple"
      })

    assert redirected_to(get(conn, ~p"/")) == ~p"/login"
  end

  test "an unavailable session store fails closed without disclosing the token", %{conn: conn} do
    conn = UserAuth.assign_scope_result(conn, {:error, :unavailable})
    assert conn.halted
    assert conn.status == 503
    refute conn.resp_body =~ "token"
  end
end
