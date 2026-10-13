defmodule Bolognesa.Music.GroupingTest do
  use ExUnit.Case, async: true
  alias Bolognesa.Libraries.Domain.ValueObjects.Inspection.MusicTags
  alias Bolognesa.Music.Domain.Policies.Grouping
  alias Bolognesa.Music.Domain.ValueObjects.{Observation, TrackMetadata}

  test "folder and library boundaries separate otherwise identical albums" do
    first = Grouping.album_key(1, "a", " Sample Album ", nil)
    assert first == Grouping.album_key(1, "a", "sample album", nil)
    refute first == Grouping.album_key(1, "b", "sample album", nil)
    refute first == Grouping.album_key(2, "a", "sample album", nil)
    assert nil == Grouping.album_key(1, "a", nil, "Sample Artist")
    assert Grouping.artist_key("  Élan!  ") == "élan!"
    assert Grouping.artist_key("Straße") == Grouping.artist_key("STRASSE")
  end

  test "compilation credit, numbers and ungrouped filename fallback" do
    observation = %Observation{
      library_id: 1,
      relative_path: "album/song.mp3",
      music_tags:
        MusicTags.from_raw(%{
          "artist" => "Solo",
          "album_artist" => "Ensemble",
          "album" => "Compilation",
          "disc" => "2",
          "track" => "3"
        })
    }

    metadata = TrackMetadata.from_observation(observation)
    assert metadata.title == "song"
    assert metadata.artist == "Solo"
    assert metadata.album_artist == "Ensemble"
    assert metadata.source_parent == "album"
    assert metadata.disc_number == 2
    assert metadata.track_number == 3

    fallback =
      TrackMetadata.from_observation(%{
        observation
        | relative_path: <<"song-", 255, ".mp3">>,
          music_tags: %MusicTags{}
      })

    assert String.valid?(fallback.title)
    assert fallback.album == nil
    assert fallback.artist == nil
  end
end
