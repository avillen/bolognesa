defmodule Bolognesa.Playback.FfmpegProgressTest do
  use ExUnit.Case, async: true
  alias Bolognesa.Playback.Infrastructure.FfmpegProgress

  test "publishes only completed numeric progress reports with explicit units" do
    state = FfmpegProgress.new()
    {state, nil} = FfmpegProgress.consume(state, {:eol, "frame=25"})
    {state, nil} = FfmpegProgress.consume(state, {:eol, "out_time_us=10427000"})
    {state, nil} = FfmpegProgress.consume(state, {:eol, "speed= 1.25x"})
    {state, report} = FfmpegProgress.consume(state, {:eol, "progress=continue"})
    assert report == %{ffmpeg_frame: 25, ffmpeg_output_ms: 10_427, ffmpeg_speed_milli: 1250}
    {state, nil} = FfmpegProgress.consume(state, {:eol, "frame=50"})
    {_state, report} = FfmpegProgress.consume(state, {:eol, "progress=end"})
    assert report == %{ffmpeg_frame: 50}
  end

  test "discards stderr, missing values, invalid numbers and oversized lines" do
    lines = [
      {:eol, "error opening /private/source.mkv"},
      {:eol, "frame=-1"},
      {:eol, "out_time_us=N/A"},
      {:eol, "speed=NaNx"},
      {:eol, "total_size=123"},
      {:noeol, String.duplicate("private", 170)},
      {:eol, "frame=999"},
      {:eol, "progress=continue"}
    ]

    state =
      Enum.reduce(lines, FfmpegProgress.new(), fn line, state ->
        {state, nil} = FfmpegProgress.consume(state, line)
        state
      end)

    {state, nil} = FfmpegProgress.consume(state, {:eol, "out_time_us=2500000"})
    {_state, report} = FfmpegProgress.consume(state, {:eol, "progress=continue"})
    assert report == %{ffmpeg_output_ms: 2500}
  end

  test "accepts scientific speeds emitted by FFmpeg within numeric bounds" do
    {state, nil} = FfmpegProgress.consume(FfmpegProgress.new(), {:eol, "speed=1.69e+03x"})
    {_state, report} = FfmpegProgress.consume(state, {:eol, "progress=end"})
    assert report == %{ffmpeg_speed_milli: 1_690_000}
    {state, nil} = FfmpegProgress.consume(FfmpegProgress.new(), {:eol, "speed=1e+99x"})
    {_state, nil} = FfmpegProgress.consume(state, {:eol, "progress=end"})
  end
end
