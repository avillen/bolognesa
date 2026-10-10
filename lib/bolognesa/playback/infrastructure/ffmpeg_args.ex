defmodule Bolognesa.Playback.Infrastructure.FfmpegArgs do
  @moduledoc "Closed FFmpeg argument list for a short sliding HLS stream."

  @spec for(:audio | :video, String.t(), String.t(), non_neg_integer()) :: [String.t()]
  def for(profile, input, directory, offset_ms) when profile in [:audio, :video] do
    seek = :erlang.float_to_binary(offset_ms / 1_000, decimals: 3)

    [
      "-hide_banner",
      "-nostdin",
      "-loglevel",
      "error",
      "-ss",
      seek,
      "-re",
      "-i",
      input,
      "-map",
      "0:v:0",
      "-map",
      "0:a:0",
      "-sn",
      "-dn"
    ] ++
      video_args(profile) ++
      [
        "-c:a",
        "aac",
        "-b:a",
        "128k",
        "-ac",
        "2",
        "-f",
        "hls",
        "-hls_segment_type",
        "mpegts",
        "-hls_time",
        "4",
        "-hls_list_size",
        "6",
        "-hls_delete_threshold",
        "2",
        "-hls_flags",
        "delete_segments+temp_file",
        "-hls_segment_filename",
        Path.join(directory, "seg-%06d.ts"),
        Path.join(directory, "index.m3u8")
      ]
  end

  defp video_args(:audio), do: ["-c:v", "copy", "-bsf:v", "h264_mp4toannexb"]

  defp video_args(:video),
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
