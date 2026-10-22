defmodule Bolognesa.Playback.TranscodeStrategyTest do
  use ExUnit.Case, async: true

  alias Bolognesa.Playback.Domain.Policies.TranscodeStrategy
  alias Bolognesa.Playback.Domain.ReadModels.Source

  test "chooses direct delivery for an inspected MP4 with H.264 and AAC" do
    assert TranscodeStrategy.choose(source("mov,mp4,m4a,3gp,3g2,mj2", "h264", "aac")) == :direct
  end

  test "converts AC-3 audio while copying H.264 video" do
    assert TranscodeStrategy.choose(source("matroska,webm", "h264", "ac3")) == :audio_only
  end

  test "converts MPEG-4 Part 2 video and AC-3 audio" do
    assert TranscodeStrategy.choose(source("avi", "mpeg4", "ac3")) == :full_transcode
  end

  test "unknown inspection keeps direct delivery" do
    assert TranscodeStrategy.choose(%Source{}) == :direct
  end

  test "chooses the first audio and video tracks" do
    source = %Source{
      format: "avi",
      tracks: [
        %{kind: :video, codec: "mpeg4"},
        %{kind: :video, codec: "h264"},
        %{kind: :audio, codec: "ac3"},
        %{kind: :audio, codec: "aac"}
      ]
    }

    assert TranscodeStrategy.choose(source) == :full_transcode
  end

  defp source(format, video, audio) do
    %Source{
      format: format,
      tracks: [%{kind: :video, codec: video}, %{kind: :audio, codec: audio}]
    }
  end
end
