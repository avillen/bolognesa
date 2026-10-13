defmodule Bolognesa.Libraries.MusicTagsTest do
  use ExUnit.Case, async: true
  alias Bolognesa.Libraries.Domain.ValueObjects.Inspection.MusicTags

  test "bounds values, allowlists keys and parses musical numbering" do
    tags =
      MusicTags.from_raw(%{
        "TITLE" => "  Sample Song  ",
        "track" => "3/12",
        "disc" => "2/2",
        "artist" => String.duplicate("x", 513),
        "date" => "2024-04-03",
        "comment" => "discard"
      })

    assert tags.title == "Sample Song"
    assert tags.track_number == 3
    assert tags.disc_number == 2
    assert tags.artist == nil
    assert tags.year == 2024
    refute Map.has_key?(Map.from_struct(tags), :comment)
  end

  test "ignores malformed values and supports aliases" do
    for raw <- [nil, [], "tags", %{}], do: assert(MusicTags.from_raw(raw) == %MusicTags{})

    tags =
      MusicTags.from_raw(%{
        "artist" => <<255>>,
        "albumartist" => " Ensemble ",
        "tracknumber" => "9999/10000",
        "discnumber" => "0",
        "year" => "999",
        "title" => 2
      })

    assert tags.album_artist == "Ensemble"
    assert tags.track_number == 9999
    assert tags.disc_number == nil
    assert tags.year == nil
    assert tags.artist == nil
    assert tags.title == nil

    for value <- ["10000", "-1", "3x", "1/", "1/0", "", String.duplicate("1", 513)] do
      assert MusicTags.from_raw(%{"track" => value}).track_number == nil
    end
  end
end
