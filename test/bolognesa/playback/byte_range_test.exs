defmodule Bolognesa.Playback.ByteRangeTest do
  use ExUnit.Case, async: true

  alias Bolognesa.Playback.Domain.ValueObjects.ByteRange

  test "selects a complete body or a single bounded byte range" do
    assert {:ok, {0, 8, 200}} = ByteRange.parse(nil, 8)
    assert {:ok, {2, 3, 206}} = ByteRange.parse("bytes=2-4", 8)
    assert {:ok, {6, 2, 206}} = ByteRange.parse("bytes=6-", 8)
    assert {:ok, {5, 3, 206}} = ByteRange.parse("bytes=-3", 8)
    assert {:ok, {6, 2, 206}} = ByteRange.parse("bytes=6-100", 8)
    assert {:ok, {0, 8, 206}} = ByteRange.parse("bytes=-20", 8)
  end

  test "rejects unsatisfiable ranges" do
    for header <- ["bytes=8-", "bytes=4-3", "bytes=-0"] do
      assert {:error, :unsatisfiable} = ByteRange.parse(header, 8)
    end

    assert {:ok, {0, 0, 200}} = ByteRange.parse(nil, 0)
    assert {:error, :unsatisfiable} = ByteRange.parse("bytes=0-", 0)
  end

  test "rejects malformed or multiple ranges before integer conversion" do
    for header <- [
          "bytes=0-1,4-5",
          "items=0-1",
          "bytes=wat",
          "bytes=+1-2",
          "bytes=1-2x",
          "bytes=1-2\n",
          "bytes=" <> String.duplicate("9", 100) <> "-"
        ] do
      assert {:error, :invalid} = ByteRange.parse(header, 8)
    end
  end
end
