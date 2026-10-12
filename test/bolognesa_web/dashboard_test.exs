defmodule BolognesaWeb.DashboardTest do
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Bolognesa.Identity
  alias Bolognesa.Infrastructure.Persistence.UserSchema

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

  test "administrator can connect to the dashboard", %{conn: conn, token: token} do
    conn = init_test_session(conn, user_token: token)

    assert {:error, {:live_redirect, %{to: "/dev/dashboard/home"}}} =
             live(conn, "/dev/dashboard")

    assert {:ok, _view, html} = live(conn, "/dev/dashboard/home")

    assert html =~ "Dashboard"
  end

  test "anonymous visitors are redirected to login", %{conn: conn} do
    assert redirected_to(get(conn, "/dev/dashboard")) == "/login"
  end

  test "members cannot access the dashboard", %{conn: conn, token: token} do
    Bolognesa.Repo.update_all(UserSchema, set: [role: "member"])
    assert conn |> init_test_session(user_token: token) |> get("/dev/dashboard") |> response(403)
  end

  test "a revoked session cannot connect to the dashboard", %{conn: conn, token: token} do
    assert :ok = Identity.end_session(token)

    assert {:error, {:redirect, %{to: "/login"}}} =
             conn |> init_test_session(user_token: token) |> live("/dev/dashboard")
  end
end
