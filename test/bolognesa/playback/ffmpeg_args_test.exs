defmodule Bolognesa.Playback.FfmpegArgsTest do
  use ExUnit.Case, async: true

  alias Bolognesa.Playback.Domain.ValueObjects.{DeliveryPlan, MediaConfiguration}
  alias Bolognesa.Playback.Infrastructure.FfmpegArgs

  test "audio strategy copies video and converts audio to AAC" do
    args = FfmpegArgs.for(plan(:audio_conversion), "/movies/original.mkv", "/tmp/session", 0)
    assert "-re" in args
    assert Enum.chunk_every(args, 2, 1, :discard) |> Enum.member?(["-c:v", "copy"])
    assert Enum.chunk_every(args, 2, 1, :discard) |> Enum.member?(["-c:a", "aac"])
    assert Enum.chunk_every(args, 2, 1, :discard) |> Enum.member?(["-ac", "2"])
    assert List.last(args) == "/tmp/session/index.m3u8"
  end

  test "both strategies build an initial cushion while retaining paced sliding output" do
    for strategy <- [:audio_conversion, :full_conversion] do
      args = FfmpegArgs.for(plan(strategy), "/movies/input.mkv", "/tmp/session", 0)
      pairs = Enum.chunk_every(args, 2, 1, :discard)
      assert ["-readrate_initial_burst", "12"] in pairs
      assert "-re" in args
      assert ["-hls_list_size", "12"] in pairs
    end
  end

  test "video strategy encodes H.264 and AAC with browser pixel format" do
    args = FfmpegArgs.for(plan(:full_conversion), "/movies/original.avi", "/tmp/session", 12_000)
    assert Enum.chunk_every(args, 2, 1, :discard) |> Enum.member?(["-c:v", "libx264"])
    assert Enum.chunk_every(args, 2, 1, :discard) |> Enum.member?(["-pix_fmt", "yuv420p"])
    assert Enum.chunk_every(args, 2, 1, :discard) |> Enum.member?(["-ss", "12.000"])

    assert Enum.chunk_every(args, 2, 1, :discard)
           |> Enum.member?(["-hls_flags", "delete_segments+temp_file"])
  end

  test "negotiated plans map absolute indexes and transform each stream independently" do
    for {mode, {video_codec, audio_codec}} <- [
          remux: {"copy", "copy"},
          audio_conversion: {"copy", "aac"},
          video_conversion: {"libx264", "copy"},
          full_conversion: {"libx264", "aac"}
        ] do
      plan = plan(mode)

      pairs =
        FfmpegArgs.for(plan, "/movies/original.mkv", "/tmp/session", 12_000)
        |> Enum.chunk_every(2, 1, :discard)

      assert ["-map", "0:3"] in pairs
      assert ["-map", "0:7"] in pairs
      assert ["-c:v", video_codec] in pairs
      assert ["-c:a", audio_codec] in pairs
      assert ["-ss", "12.000"] in pairs

      if video_codec == "libx264" do
        assert ["-profile:v", "baseline"] in pairs
        assert ["-level:v", "4.1"] in pairs
        assert ["-maxrate:v", "8M"] in pairs
        assert ["-bufsize:v", "16M"] in pairs
        assert ["-vf", "scale=1920:1080:flags=fast_bilinear"] in pairs
        assert ["-r", "30.0"] in pairs
      end

      if audio_codec == "aac" do
        assert ["-profile:a", "aac_low"] in pairs
        assert ["-ar", "48000"] in pairs
      end
    end
  end

  test "negotiated silent output has no audio map or encoder" do
    plan = plan(:video_conversion)

    plan = %{
      plan
      | audio_index: nil,
        audio_action: :absent,
        configuration: %{plan.configuration | audio: nil}
    }

    args = FfmpegArgs.for(plan, "/movies/silent.mkv", "/tmp/session", 0)
    pairs = Enum.chunk_every(args, 2, 1, :discard)
    assert "-an" in args
    refute ["-map", "0:7"] in pairs
    refute "-c:a" in args
  end

  defp plan(mode) do
    %DeliveryPlan{
      revision: 1,
      video_index: 3,
      audio_index: 7,
      mode: mode,
      video_action: if(mode in [:remux, :audio_conversion], do: :copy, else: :h264),
      audio_action: if(mode in [:remux, :video_conversion], do: :copy, else: :aac),
      transport: :hls_js,
      reason: :remux_supported,
      configuration: %MediaConfiguration{
        container: :mpegts,
        mime: "video/mp2t",
        video: %{
          codec_string: "avc1.42C029",
          width: 1920,
          height: 1080,
          frame_rate: 30.0,
          bit_rate: 8_000_000
        },
        audio: %{codec_string: "mp4a.40.2", sample_rate: 48_000, channels: 2, bit_rate: 128_000}
      }
    }
  end
end
