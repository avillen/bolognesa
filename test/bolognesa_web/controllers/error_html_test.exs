defmodule BolognesaWeb.ErrorHTMLTest do
  use BolognesaWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    assert render_to_string(BolognesaWeb.ErrorHTML, "404", "html", []) == "Not Found"
  end

  test "renders 500.html" do
    assert render_to_string(BolognesaWeb.ErrorHTML, "500", "html", []) == "Internal Server Error"
  end

  test "HTTP error text follows the browser locale", %{conn: conn} do
    conn = put_req_header(conn, "accept-language", "es-ES")
    assert BolognesaWeb.ErrorHTML.render("404.html", %{conn: conn}) == "Página no encontrada"

    assert BolognesaWeb.ErrorHTML.render("500.html", %{conn: conn}) ==
             "Error interno del servidor"
  end
end
