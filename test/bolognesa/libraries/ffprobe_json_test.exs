defmodule Bolognesa.Libraries.FfprobeJsonTest do
  use ExUnit.Case, async: true

  alias Bolognesa.Libraries.Infrastructure.FfprobeJson

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
