defmodule BolognesaWeb.ParamsTest do
  use ExUnit.Case, async: true

  alias BolognesaWeb.Params

  test "positive_integer accepts only whole positive decimal text" do
    assert Params.positive_integer("42") == 42
    assert Params.positive_integer("0") == nil
    assert Params.positive_integer("-3") == nil
    assert Params.positive_integer("4x") == nil
    assert Params.positive_integer(nil) == nil
    assert Params.positive_integer(7) == nil
  end

  test "integer keeps the caller's bounds" do
    assert Params.integer("0", 0..10) == 0
    assert Params.integer("11", 0..10) == nil
  end

  test "page falls back to the first page outside 1..100_000" do
    assert Params.page("3") == 3
    assert Params.page("100001") == 1
    assert Params.page(nil) == 1
  end
end
