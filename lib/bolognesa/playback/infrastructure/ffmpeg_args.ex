defmodule Bolognesa.Playback.Infrastructure.FfmpegArgs do
  @moduledoc "Closed FFmpeg argument list for a short sliding HLS stream."

  alias Bolognesa.Playback.Domain.ValueObjects.DeliveryPlan

  @spec for(
          DeliveryPlan.t(),
          String.t(),
          String.t(),
          non_neg_integer()
        ) :: [
          String.t()
        ]
  def for(%DeliveryPlan{} = plan, input, directory, offset_ms) do
    seek = :erlang.float_to_binary(offset_ms / 1_000, decimals: 3)
    audio_map = if plan.audio_index, do: ["-map", "0:#{plan.audio_index}"], else: []

    [
      "-hide_banner",
      "-nostdin",
      "-nostats",
      "-stats_period",
      "1",
      "-progress",
      "pipe:1",
      "-loglevel",
      "error",
      "-ss",
      seek,
      "-re",
      "-readrate_initial_burst",
      "12",
      "-i",
      input,
      "-map",
      "0:#{plan.video_index}"
    ] ++
      audio_map ++
      ["-sn", "-dn"] ++
      planned_video_args(plan) ++ planned_audio_args(plan.audio_action) ++ output_args(directory)
  end

  defp planned_video_args(%DeliveryPlan{video_action: :copy}),
    do: ["-c:v", "copy", "-bsf:v", "h264_mp4toannexb"]

  defp planned_video_args(%DeliveryPlan{video_action: :h264, configuration: config}) do
    video = config.video

    encoded_video_args() ++
      [
        "-profile:v",
        "baseline",
        "-level:v",
        "4.1",
        "-maxrate:v",
        "8M",
        "-bufsize:v",
        "16M",
        "-vf",
        "scale=#{video.width}:#{video.height}:flags=fast_bilinear",
        "-r",
        Float.to_string(video.frame_rate)
      ]
  end

  defp planned_audio_args(:copy), do: ["-c:a", "copy"]
  defp planned_audio_args(:absent), do: ["-an"]

  defp planned_audio_args(:aac),
    do: ["-c:a", "aac", "-profile:a", "aac_low", "-b:a", "128k", "-ar", "48000", "-ac", "2"]

  defp output_args(directory) do
    [
      "-f",
      "hls",
      "-hls_segment_type",
      "mpegts",
      "-hls_time",
      "4",
      "-hls_list_size",
      "12",
      "-hls_delete_threshold",
      "2",
      "-hls_flags",
      "delete_segments+temp_file",
      "-hls_segment_filename",
      Path.join(directory, "seg-%06d.ts"),
      Path.join(directory, "index.m3u8")
    ]
  end

  defp encoded_video_args,
    do: [
      "-c:v",
      "libx264",
      "-preset",
      "ultrafast",
      "-crf",
      "25",
      "-pix_fmt",
      "yuv420p",
      "-threads",
      "2",
      "-force_key_frames",
      "expr:gte(t,n_forced*4)"
    ]
end
