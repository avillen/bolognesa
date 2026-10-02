defmodule BolognesaWeb.PageControllerTest do
  use BolognesaWeb.ConnCase

  test "GET / requires authentication", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/setup"
  end
end
