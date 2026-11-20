defmodule Bolognesa.ReadQueryTest do
  use ExUnit.Case, async: true

  alias Bolognesa.ReadQuery

  test "validates text, page and optional library together" do
    assert :ok = ReadQuery.validate("", 1, nil)
    assert :ok = ReadQuery.validate(String.duplicate("a", 256), 100_000, 1)
    assert {:error, :invalid_query} = ReadQuery.validate(String.duplicate("a", 257), 1, nil)
    assert {:error, :invalid_query} = ReadQuery.validate(<<255>>, 1, nil)
    assert {:error, :invalid_query} = ReadQuery.validate(nil, 1, nil)
    assert {:error, :invalid_page} = ReadQuery.validate("", 0, nil)
    assert {:error, :invalid_page} = ReadQuery.validate("", 100_001, nil)
    assert {:error, :invalid_query} = ReadQuery.validate("", 1, 0)
  end

  test "ids are positive integers" do
    assert :ok = ReadQuery.validate_id(1)
    assert {:error, :not_found} = ReadQuery.validate_id(0)
    assert {:error, :not_found} = ReadQuery.validate_id("1")
    assert :ok = ReadQuery.validate_optional_id(nil)
    assert {:error, :invalid_query} = ReadQuery.validate_optional_id(0)
  end
end
