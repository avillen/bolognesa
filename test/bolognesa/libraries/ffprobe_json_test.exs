defmodule Bolognesa.Libraries.FfprobeJsonTest do
  use ExUnit.Case, async: true

  alias Bolognesa.Libraries.Infrastructure.Services.FfprobeJson

  test "music ignores attached artwork with unknown dimensions while validating audio" do
    artwork = %{
      "codec_type" => "video",
      "codec_name" => "mjpeg",
      "width" => 0,
      "height" => 0,
      "disposition" => %{"attached_pic" => 1}
    }

    audio = %{"codec_type" => "audio", "codec_name" => "mp3", "channels" => 2}

    encode = fn streams ->
      Jason.encode!(%{
        "format" => %{"format_name" => "mp3", "duration" => "182.740571"},
        "streams" => streams
      })
    end

    assert {:ok, media} = FfprobeJson.parse(encode.([audio, artwork]), :music)
    assert [%{kind: :audio, codec: "mp3", channels: 2}] = media.tracks
    assert media.duration_ms == 182_741
    assert {:error, :invalid_output} = FfprobeJson.parse(encode.([artwork]), :music)
    assert {:error, :invalid_output} = FfprobeJson.parse(encode.([audio, artwork]))

    assert {:error, :invalid_output} =
             FfprobeJson.parse(encode.([audio, Map.delete(artwork, "disposition")]), :music)

    assert {:error, :invalid_output} =
             FfprobeJson.parse(encode.([%{audio | "channels" => 0}, artwork]), :music)
  end

  test "normalizes format, duration and ordered tracks while discarding private tags" do
    json =
      ~s({"format":{"format_name":"matroska","duration":"2.5","tags":{"title":"secret"}},"streams":[{"codec_type":"video","codec_name":"h264","width":1920,"height":1080,"tags":{"language":"eng","title":"secret"}},{"codec_type":"audio","codec_name":"aac","channels":2}]})

    assert {:ok, media} = FfprobeJson.parse(json)
    assert media.format == "matroska"
    assert media.duration_ms == 2_500

    assert [%{kind: :video, codec: "h264", language: "eng"}, %{kind: :audio, channels: 2}] =
             media.tracks

    refute inspect(media) =~ "secret"
  end

  test "music imports stream tags used by Ogg and Opus without artwork credits" do
    json =
      Jason.encode!(%{
        "format" => %{"format_name" => "ogg"},
        "streams" => [
          %{"codec_type" => "video", "tags" => %{"title" => "Artwork"}},
          %{
            "codec_type" => "audio",
            "codec_name" => "opus",
            "tags" => %{
              "TITLE" => "Song",
              "ARTIST" => "Ensemble",
              "ALBUM" => "Release",
              "TRACKNUMBER" => "3/12"
            }
          }
        ]
      })

    assert {:ok, media} = FfprobeJson.parse(json, :music)
    assert media.music_tags.title == "Song"
    assert media.music_tags.artist == "Ensemble"
    assert media.music_tags.album == "Release"
    assert media.music_tags.track_number == 3
    assert {:ok, video} = FfprobeJson.parse(json)
    assert video.music_tags == nil
  end

  test "music requires audio and retains only sanitized format tags" do
    json =
      Jason.encode!(%{
        "format" => %{"tags" => %{"title" => "Sample Song"}},
        "streams" => [
          %{"codec_type" => "video", "codec_name" => "mjpeg"},
          %{"codec_type" => "audio", "codec_name" => "mp3"}
        ]
      })

    assert {:ok, media} = FfprobeJson.parse(json, :music)
    assert media.music_tags.title == "Sample Song"
    assert {:ok, video} = FfprobeJson.parse(json)
    assert video.music_tags == nil

    assert {:error, :invalid_output} =
             FfprobeJson.parse(~s({"format":{},"streams":[{"codec_type":"video"}]}), :music)
  end

  test "allows absent duration and rejects malformed or unbounded fields" do
    assert {:ok, %{duration_ms: nil}} = FfprobeJson.parse(~s({"format":{},"streams":[]}))
    assert {:error, :invalid_output} = FfprobeJson.parse("not json")

    assert {:error, :invalid_output} =
             FfprobeJson.parse(~s({"format":{"duration":"NaN"},"streams":[]}))

    assert {:error, :invalid_output} =
             FfprobeJson.parse(~s({"format":{},"streams":[{"codec_type":"video","width":-1}]}))

    too_many =
      Jason.encode!(%{
        "format" => %{},
        "streams" => List.duplicate(%{"codec_type" => "audio"}, 129)
      })

    assert {:error, :invalid_output} = FfprobeJson.parse(too_many)
  end
end
