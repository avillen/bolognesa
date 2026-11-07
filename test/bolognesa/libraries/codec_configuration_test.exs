defmodule Bolognesa.Libraries.CodecConfigurationTest do
  use ExUnit.Case, async: true
  alias Bolognesa.Libraries.Infrastructure.Services.CodecConfiguration
  alias Bolognesa.Libraries.Infrastructure.Services.FfprobeJson

  @avcc Base.decode16!(
          "0142C029FFE1001C6742C029DA01E0089F97016A04040280000003008000001E078C195001000468CE1F20"
        )

  test "AVC derives profile, compatibility and level from configuration bytes" do
    assert CodecConfiguration.identifier("h264", @avcc, "avc1") == "avc1.42C029"
    assert CodecConfiguration.identifier("h264", @avcc, "avc3") == nil
    assert CodecConfiguration.identifier("h264", <<1, 100, 0, 41>>, "avc1") == nil

    for length <- 0..(byte_size(@avcc) - 1) do
      assert CodecConfiguration.identifier("h264", binary_part(@avcc, 0, length), "avc1") == nil
    end

    assert CodecConfiguration.identifier("h264", @avcc <> <<0>>, "avc1") == nil
    assert CodecConfiguration.identifier("h264", :binary.copy(@avcc, 1000), "avc1") == nil
  end

  test "HEVC retains sample-entry type, reversed compatibility flags, tier and constraints" do
    record =
      <<1, 1, 0x60000000::32, 0xB00000000000::48, 93, 0xF000::16, 0xFC, 0xFD, 0xF8, 0xF8, 0::16,
        15, 3, 0xA0, 1::16, 3::16, 64, 1, 1, 0xA1, 1::16, 3::16, 66, 1, 1, 0xA2, 1::16, 3::16, 68,
        1, 1>>

    assert CodecConfiguration.identifier("hevc", record, "hvc1") == "hvc1.1.6.L93.B0"
    assert CodecConfiguration.identifier("hevc", record, "hev1") == "hev1.1.6.L93.B0"
    assert CodecConfiguration.identifier("hevc", record, nil) == nil

    for length <- 0..(byte_size(record) - 1) do
      assert CodecConfiguration.identifier("hevc", binary_part(record, 0, length), "hvc1") == nil
    end
  end

  test "AAC requires an explicit supported AudioSpecificConfig" do
    assert CodecConfiguration.identifier("aac", <<0x11, 0x90, 0x56, 0xE5, 0>>, "mp4a") ==
             "mp4a.40.2"

    assert CodecConfiguration.identifier("aac", <<0>>, "mp4a") == nil
    assert CodecConfiguration.identifier("aac", <<0xF9, 0x90>>, "mp4a") == nil
    assert CodecConfiguration.identifier("vp9", <<1, 2>>, nil) == nil
  end

  test "bounded ffprobe hex dumps become normalized facts without raw bytes" do
    dump =
      "\n00000000: 0142 c029 ffe1 001c 6742 c029 da01 e008  .B.)....gB.)....\n00000010: 9f97 016a 0404 0280 0000 0300 8000 001e  ...j............\n00000020: 078c 1950 0100 0468 ce1f 20              ...P...h.. \n"

    stream = %{
      "codec_type" => "video",
      "codec_name" => "h264",
      "codec_tag_string" => "avc1",
      "extradata" => dump
    }

    encode = fn stream -> Jason.encode!(%{"format" => %{}, "streams" => [stream]}) end
    assert {:ok, %{tracks: [track]}} = FfprobeJson.parse(encode.(stream))
    assert Map.get(track, :codec_string) == "avc1.42C029"
    refute Map.has_key?(Map.from_struct(track), :extradata)

    for invalid <- [
          nil,
          "00000000: 0142 zz29  bad",
          String.duplicate("x", 20_000),
          String.replace(dump, "00000010", "00000011")
        ] do
      assert {:ok, %{tracks: [track]}} =
               FfprobeJson.parse(encode.(%{stream | "extradata" => invalid}))

      assert Map.get(track, :codec_string) == nil
    end
  end
end
