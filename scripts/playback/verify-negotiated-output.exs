# Run with: mix run --no-start scripts/playback/verify-negotiated-output.exs tmp/negotiation-matrix
# Disposable synthetic media only. No application/database or private library is read.
defmodule NegotiatedOutputVerification do
  alias Bolognesa.Libraries.Infrastructure.Services.FfprobeJson
  alias Bolognesa.Playback.Domain.Policies.Negotiation
  alias Bolognesa.Playback.Domain.ReadModels.{Source, TechnicalTrack}
  alias Bolognesa.Playback.Infrastructure.FfmpegArgs

  @spec run(String.t()) :: :ok
  def run(directory) do
    File.mkdir_p!(directory)
    base = Path.join(directory, "direct.mp4")

    command!("ffmpeg", [
      "-y",
      "-v",
      "error",
      "-f",
      "lavfi",
      "-i",
      "testsrc2=size=320x180:rate=24",
      "-f",
      "lavfi",
      "-i",
      "sine=frequency=440:sample_rate=48000",
      "-t",
      "20",
      "-c:v",
      "libx264",
      "-preset",
      "ultrafast",
      "-profile:v",
      "baseline",
      "-level:v",
      "4.1",
      "-pix_fmt",
      "yuv420p",
      "-g",
      "48",
      "-maxrate",
      "8M",
      "-bufsize",
      "16M",
      "-x264-params",
      "colorprim=bt709:transfer=bt709:colormatrix=bt709",
      "-c:a",
      "aac",
      "-profile:a",
      "aac_low",
      "-b:a",
      "128k",
      "-ac",
      "2",
      "-movflags",
      "+faststart",
      base
    ])

    fixtures = [
      {"remux.mkv", ["-c", "copy"], :remux},
      {"audio.mkv", ["-c:v", "copy", "-c:a", "ac3", "-b:a", "192k"], :audio_conversion},
      {"video.mp4", hevc() ++ ["-c:a", "copy"], :video_conversion},
      {"both.mp4", hevc() ++ ["-c:a", "ac3", "-b:a", "192k"], :full_conversion},
      {"silent.mkv", ["-c:v", "copy", "-an"], :remux}
    ]

    for {name, args, mode} <- fixtures do
      input = Path.join(directory, name)
      command!("ffmpeg", ["-y", "-v", "error", "-i", base] ++ args ++ [input])
      verify(input, mode, directory)
    end

    # Matched source and duration: compare this full encode with remux.mkv's copy result.
    verify(Path.join(directory, "remux.mkv"), :full_conversion, directory)
  end

  @spec verify_main_copy(String.t()) :: :ok
  def verify_main_copy(directory) do
    File.mkdir_p!(directory)

    for {name, size, rate, level, codec} <- [
          {"main-720.mkv", "1280x720", "25", "3.1", "avc1.4D401F"},
          {"main-1080.mkv", "1920x1080", "30", "4.1", "avc1.4D4029"}
        ] do
      input = Path.join(directory, name)

      command!("ffmpeg", [
        "-y",
        "-v",
        "error",
        "-f",
        "lavfi",
        "-i",
        "testsrc2=size=#{size}:rate=#{rate}",
        "-f",
        "lavfi",
        "-i",
        "sine=frequency=440:sample_rate=44100",
        "-t",
        "20",
        "-c:v",
        "libx264",
        "-preset",
        "veryfast",
        "-threads",
        "2",
        "-profile:v",
        "main",
        "-level:v",
        level,
        "-pix_fmt",
        "yuv420p",
        "-g",
        rate,
        "-b:v",
        "2M",
        "-maxrate",
        "8M",
        "-bufsize",
        "16M",
        "-c:a",
        "libmp3lame",
        "-ac",
        "2",
        "-b:a",
        "128k",
        input
      ])

      media = inspect!(input)
      video = Enum.find(media.tracks, &(&1.kind == :video))
      audio = Enum.find(media.tracks, &(&1.kind == :audio))
      ^codec = video.codec_string
      "Main" = video.profile
      "mp3" = audio.codec
      nil = video.color_transfer
      nil = video.color_primaries
      nil = video.color_space
      verify(input, :audio_conversion, directory)
    end
  end

  @spec verify_anamorphic(String.t()) :: :ok
  def verify_anamorphic(directory) do
    File.mkdir_p!(directory)
    input = Path.join(directory, "anamorphic.mp4")

    command!("ffmpeg", [
      "-y",
      "-v",
      "error",
      "-f",
      "lavfi",
      "-i",
      "testsrc2=size=720x576:rate=25,setsar=64/45",
      "-t",
      "1",
      "-c:v",
      "libx264",
      "-profile:v",
      "high",
      "-pix_fmt",
      "yuv420p",
      "-x264-params",
      "colorprim=bt709:transfer=bt709:colormatrix=bt709",
      input
    ])

    media = inspect!(input)

    source = %Source{
      revision: 1,
      format: media.format,
      duration_ms: media.duration_ms,
      tracks: Enum.map(media.tracks, &struct!(TechnicalTrack, Map.from_struct(&1)))
    }

    {:ok, candidates} = Negotiation.candidates(source)
    candidate = Enum.find(candidates, &(&1.plan.mode == :video_conversion))
    plan = %{candidate.plan | transport: :hls_js}
    args = FfmpegArgs.for(plan, Path.expand(input), Path.expand(directory), 0)
    command!("ffmpeg", ["-y" | args])

    result =
      command!("ffprobe", [
        "-v",
        "quiet",
        "-show_entries",
        "stream=sample_aspect_ratio,display_aspect_ratio,width,height",
        "-of",
        "json",
        Path.join(directory, "index.m3u8")
      ])
      |> Jason.decode!()

    [video] = result["streams"]

    if video["display_aspect_ratio"] != "16:9",
      do: raise("Anamorphic display geometry changed: #{video["display_aspect_ratio"]}")

    IO.puts(
      Jason.encode!(%{
        anamorphic: true,
        width: video["width"],
        height: video["height"],
        sample_aspect_ratio: video["sample_aspect_ratio"],
        display_aspect_ratio: video["display_aspect_ratio"]
      })
    )
  end

  defp hevc do
    [
      "-c:v",
      "libx265",
      "-preset",
      "ultrafast",
      "-x265-params",
      "pools=1:frame-threads=1:colorprim=bt709:transfer=bt709:colormatrix=bt709:log-level=error"
    ]
  end

  defp verify(input, mode, directory) do
    media = inspect!(input)

    source = %Source{
      revision: 1,
      format: media.format,
      duration_ms: media.duration_ms,
      tracks: Enum.map(media.tracks, &struct!(TechnicalTrack, Map.from_struct(&1)))
    }

    {:ok, candidates} = Negotiation.candidates(source)
    candidate = Enum.find(candidates, &(&1.plan.mode == mode))

    if is_nil(candidate),
      do: raise("Actual inspection cannot issue #{mode} for #{Path.basename(input)}")

    plan = %{candidate.plan | transport: :hls_js}
    output = Path.join(directory, "#{Path.basename(input)}-#{mode}")
    File.mkdir_p!(output)

    # Offline codec verification removes pacing only. Real-app verification retains it.
    args = FfmpegArgs.for(plan, Path.expand(input), Path.expand(output), 0)
    args = Enum.reject(args, &(&1 == "-re"))
    burst = Enum.find_index(args, &(&1 == "-readrate_initial_burst"))
    args = args |> List.delete_at(burst) |> List.delete_at(burst)
    timing = command!("/usr/bin/time", ["-p", "ffmpeg", "-y" | args])
    File.write!(Path.join(output, "encode.log"), timing)

    File.write!(
      Path.join(output, "probe.json"),
      Jason.encode!(%{
        generation: "synthetic-output",
        candidates: [
          %{
            id: candidate.id,
            transports: candidate.transports,
            configuration: Map.from_struct(plan.configuration)
          }
        ]
      })
    )

    manifest = Path.join(output, "index.m3u8")
    actual = inspect!(manifest)
    video = Enum.find(actual.tracks, &(&1.kind == :video))
    audio = Enum.find(actual.tracks, &(&1.kind == :audio))
    "h264" = video.codec
    expected_video = Enum.find(media.tracks, &(&1.kind == :video))

    expected_profile =
      if plan.video_action == :copy, do: expected_video.profile, else: "Constrained Baseline"

    expected_level = if plan.video_action == :copy, do: expected_video.level, else: 41
    ^expected_profile = video.profile
    ^expected_level = video.level
    "yuv420p" = video.pixel_format
    true = video.width == plan.configuration.video.width
    true = video.height == plan.configuration.video.height

    if plan.audio_action == :absent do
      nil = audio
    else
      "aac" = audio.codec
      "LC" = audio.profile
      2 = audio.channels
      48_000 = audio.sample_rate
    end

    normalized = Path.join(output, "codec-record.mp4")
    command!("ffmpeg", ["-y", "-v", "error", "-i", manifest, "-c", "copy", normalized])
    records = inspect!(normalized)
    actual_video = Enum.find(records.tracks, &(&1.kind == :video))

    if actual_video.codec_string != plan.configuration.video.codec_string,
      do: raise("Actual AVC configuration differs from the advertised codec")

    copied = if plan.video_action == :copy, do: copied_video?(input, manifest, output), else: nil
    if copied == false, do: raise("Copied video VCL bytes differ for #{Path.basename(input)}")

    audio_copy =
      if plan.audio_action == :copy, do: copied_audio!(input, manifest, output), else: nil

    result = %{
      fixture: Path.basename(input),
      mode: mode,
      video: plan.video_action,
      audio: plan.audio_action,
      copied_video_vcl_equal: copied,
      copied_audio: audio_copy,
      timing: String.trim(timing)
    }

    IO.puts(Jason.encode!(result))
  end

  defp copied_video?(input, manifest, directory) do
    hashes =
      for {path, label} <- [{input, "source"}, {manifest, "output"}] do
        output = Path.join(directory, "#{label}.h264")

        command!("ffmpeg", [
          "-y",
          "-v",
          "error",
          "-i",
          path,
          "-map",
          "0:v:0",
          "-c:v",
          "copy",
          "-bsf:v",
          "h264_mp4toannexb,filter_units=remove_types=6|7|8|9",
          "-f",
          "h264",
          output
        ])

        :crypto.hash(:sha256, File.read!(output))
      end

    Enum.at(hashes, 0) == Enum.at(hashes, 1)
  end

  defp inspect!(path) do
    json =
      command!("ffprobe", [
        "-v",
        "quiet",
        "-show_data",
        "-show_format",
        "-show_streams",
        "-of",
        "json",
        path
      ])

    {:ok, media} = FfprobeJson.parse(json)
    media
  end

  defp copied_audio!(input, manifest, directory) do
    [source, delivered] =
      for {path, label} <- [{input, "source"}, {manifest, "output"}] do
        output = Path.join(directory, "#{label}.aac")

        command!("ffmpeg", [
          "-y",
          "-v",
          "error",
          "-i",
          path,
          "-map",
          "0:a:0",
          "-c:a",
          "copy",
          "-f",
          "adts",
          output
        ])

        adts_payloads(File.read!(output), [])
      end

    # Input -ss 0 can exclude Matroska's first AAC priming packet before video start.
    # Require exact ordered payloads and report the leading trim explicitly.
    trim = Enum.find(0..2, &(Enum.drop(source, &1) == delivered))
    if is_nil(trim), do: raise("Copied AAC payload sequence differs")
    %{payloads_equal: true, leading_packets_trimmed: trim, output_packets: length(delivered)}
  end

  defp adts_payloads(<<>>, acc), do: Enum.reverse(acc)

  defp adts_payloads(
         <<255, 15::4, _::3, protection::1, _::8, _::6, high::2, middle, low::3, _::5, _::8,
           rest::binary>>,
         acc
       ) do
    length = Bitwise.bsl(high, 11) + Bitwise.bsl(middle, 3) + low
    payload_size = length - 7
    <<frame::binary-size(^payload_size), tail::binary>> = rest
    payload = if protection == 1, do: frame, else: binary_part(frame, 2, byte_size(frame) - 2)
    adts_payloads(tail, [:crypto.hash(:sha256, payload) | acc])
  end

  defp command!(executable, args) do
    case System.cmd(executable, args, stderr_to_stdout: true) do
      {output, 0} ->
        output

      {output, status} ->
        raise("#{Path.basename(executable)} failed (#{status}): #{String.slice(output, 0, 2000)}")
    end
  end
end

case System.argv() do
  [directory] -> NegotiatedOutputVerification.run(directory)
  [directory, "--main-copy"] -> NegotiatedOutputVerification.verify_main_copy(directory)
  [directory, "--anamorphic"] -> NegotiatedOutputVerification.verify_anamorphic(directory)
  _ -> raise "Pass a disposable output directory under tmp/"
end
