defmodule Bolognesa.Playback.FfmpegArgsTest do
  use ExUnit.Case, async: true

  alias Bolognesa.Playback.Infrastructure.FfmpegArgs

  test "audio profile copies video and converts audio to AAC" do
    args = FfmpegArgs.for(:audio, "/movies/original.mkv", "/tmp/session", 0)
    assert Enum.chunk_every(args, 2, 1, :discard) |> Enum.member?(["-re", "-i"])
    assert Enum.chunk_every(args, 2, 1, :discard) |> Enum.member?(["-c:v", "copy"])
    assert Enum.chunk_every(args, 2, 1, :discard) |> Enum.member?(["-c:a", "aac"])
    assert Enum.chunk_every(args, 2, 1, :discard) |> Enum.member?(["-ac", "2"])
    assert List.last(args) == "/tmp/session/index.m3u8"
  end

  test "video profile encodes H.264 and AAC with browser pixel format" do
    args = FfmpegArgs.for(:video, "/movies/original.avi", "/tmp/session", 12_000)
    assert Enum.chunk_every(args, 2, 1, :discard) |> Enum.member?(["-c:v", "libx264"])
    assert Enum.chunk_every(args, 2, 1, :discard) |> Enum.member?(["-pix_fmt", "yuv420p"])
    assert Enum.chunk_every(args, 2, 1, :discard) |> Enum.member?(["-ss", "12.000"])

    assert Enum.chunk_every(args, 2, 1, :discard)
           |> Enum.member?(["-hls_flags", "delete_segments+temp_file"])
  end
end
