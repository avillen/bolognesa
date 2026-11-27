defmodule BolognesaWeb.MediaComponentsTest do
  use BolognesaWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias BolognesaWeb.MediaComponents

  defp pagination(page, total) do
    render_component(&MediaComponents.pagination/1,
      id: "movies",
      label: "Páginas",
      page: page,
      page_size: 24,
      total: total,
      path: &"/movies?page=#{&1}"
    )
    |> LazyHTML.from_fragment()
  end

  defp href(html, id), do: html |> LazyHTML.query("##{id}") |> LazyHTML.attribute("href")

  test "pagination is hidden when everything fits on one page" do
    assert pagination(1, 24) |> LazyHTML.query("nav") |> Enum.empty?()
  end

  test "pagination links to the neighbouring pages that exist" do
    first = pagination(1, 50)
    assert LazyHTML.attribute(LazyHTML.query(first, "nav"), "id") == ["movies-pagination"]
    assert href(first, "movies-previous") == []
    assert href(first, "movies-next") == ["/movies?page=2"]

    middle = pagination(2, 50)
    assert href(middle, "movies-previous") == ["/movies?page=1"]
    assert href(middle, "movies-next") == ["/movies?page=3"]

    last = pagination(3, 50)
    assert href(last, "movies-previous") == ["/movies?page=2"]
    assert href(last, "movies-next") == []
  end
end
