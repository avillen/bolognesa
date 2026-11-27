defmodule BolognesaWeb.MediaComponentsTest do
  use BolognesaWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias BolognesaWeb.MediaComponents

  defp pagination(page, total) when is_integer(total), do: render_pagination(page, total: total)
  defp pagination(page, has_next), do: render_pagination(page, has_next: has_next)

  defp render_pagination(page, extent) do
    render_component(
      &MediaComponents.pagination/1,
      [id: "movies", label: "Páginas", page: page, page_size: 24, path: &"/movies?page=#{&1}"] ++
        extent
    )
    |> LazyHTML.from_fragment()
  end

  defp hidden?(html), do: html |> LazyHTML.query("nav") |> Enum.empty?()

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

  test "counted pagination keeps hiding on pages past a single-page total" do
    assert hidden?(pagination(3, 10))
  end

  test "uncounted pagination follows the lookahead and keeps a way back from empty deep pages" do
    assert hidden?(pagination(1, false))

    first = pagination(1, true)
    assert href(first, "movies-previous") == []
    assert href(first, "movies-next") == ["/movies?page=2"]

    beyond = pagination(9, false)
    assert href(beyond, "movies-previous") == ["/movies?page=8"]
    assert href(beyond, "movies-next") == []
  end

  test "pagination refuses a missing extent instead of comparing against nil" do
    assert_raise ArgumentError, fn ->
      render_component(&MediaComponents.pagination/1,
        id: "movies",
        label: "Páginas",
        page: 1,
        page_size: 24,
        path: &"/movies?page=#{&1}"
      )
    end
  end
end
