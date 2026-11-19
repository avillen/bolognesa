defmodule Bolognesa.ReadQueryTest do
  use ExUnit.Case, async: true

  alias Bolognesa.ReadQuery

  test "validates text, page and optional library together" do
    assert ReadQuery.valid?("", 1, nil)
    assert ReadQuery.valid?(String.duplicate("a", 256), 100_000, 1)
    refute ReadQuery.valid?(String.duplicate("a", 257), 1, nil)
    refute ReadQuery.valid?(<<255>>, 1, nil)
    refute ReadQuery.valid?(nil, 1, nil)
    refute ReadQuery.valid?("", 0, nil)
    refute ReadQuery.valid?("", 100_001, nil)
    refute ReadQuery.valid?("", 1, 0)
  end

  test "ids are positive integers" do
    assert ReadQuery.valid_id?(1)
    refute ReadQuery.valid_id?(0)
    refute ReadQuery.valid_id?("1")
    assert ReadQuery.valid_optional_id?(nil)
  end
end
