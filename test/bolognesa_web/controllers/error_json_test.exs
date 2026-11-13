defmodule BolognesaWeb.ErrorJSONTest do
  alias BolognesaWeb.ErrorJSON, as: BolognesaWebErrorJSON
  use BolognesaWeb.ConnCase, async: true

  test "renders 404" do
    assert BolognesaWebErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert BolognesaWebErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
