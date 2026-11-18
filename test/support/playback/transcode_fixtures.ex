defmodule Bolognesa.TranscodeFixtures do
  @moduledoc false
  import ExUnit.Callbacks
  alias Bolognesa.Infrastructure.LocalSourcePath
  alias Bolognesa.Playback.Domain.Policies.Negotiation
  alias Bolognesa.Playback.Domain.ReadModels.Source
  alias Bolognesa.Playback.Domain.ReadModels.TechnicalTrack
  alias Bolognesa.Playback.Domain.ValueObjects.DeliveryPlan
  alias Bolognesa.Playback.Infrastructure.TranscodeManager

  @doc "Configure a fake FFmpeg and private transcode root around a negotiated source."
  @spec transcode_source(map()) :: %{source: Source.t()}
  def transcode_source(_context) do
    base =
      Path.join(
        hd(Application.fetch_env!(:bolognesa, :library_roots)),
        "transcode-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(base)
    {:ok, root} = LocalSourcePath.canonical_directory(base)
    source_path = Path.join(root, "original.avi")
    File.write!(source_path, "controlled source")
    {:ok, stat} = File.stat(source_path, time: :posix)
    executable = Path.join(root, "fake-ffmpeg")
    File.write!(executable, "#!/bin/sh\nwhile :; do sleep 1; done\n")
    File.chmod!(executable, 0o700)
    previous_root = Application.get_env(:bolognesa, :transcode_root)
    previous_executable = Application.get_env(:bolognesa, :ffmpeg_executable)

    transcode_root =
      Path.join(System.tmp_dir!(), "hls-test-#{System.unique_integer([:positive])}")

    Application.put_env(:bolognesa, :transcode_root, transcode_root)
    Application.put_env(:bolognesa, :ffmpeg_executable, executable)

    on_exit(fn ->
      TranscodeManager.stop_all()
      restore(:transcode_root, previous_root)
      restore(:ffmpeg_executable, previous_executable)
      File.rm_rf!(root)
      File.rm_rf!(transcode_root)
    end)

    source = %Source{
      path: root,
      relative_path: "original.avi",
      size_bytes: stat.size,
      modified_at: DateTime.from_unix!(stat.mtime),
      revision: 1,
      duration_ms: 60_000
    }

    {source, _plan} = negotiated_source(source)
    %{source: source}
  end

  @spec attach_lifecycle() :: :ok
  def attach_lifecycle do
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach_many(
        handler,
        [
          [:bolognesa, :playback, :session, :started],
          [:bolognesa, :playback, :session, :closed],
          [:bolognesa, :playback, :session, :preparation],
          [:bolognesa, :playback, :session, :paced]
        ],
        &__MODULE__.handle_telemetry/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  @spec handle_telemetry([atom()], map(), map(), pid()) :: any()
  def handle_telemetry(event, measurements, metadata, caller),
    do: send(caller, {event, measurements, metadata})

  defp restore(key, nil), do: Application.delete_env(:bolognesa, key)
  defp restore(key, value), do: Application.put_env(:bolognesa, key, value)

  @spec plan(Source.t(), DeliveryPlan.mode()) :: DeliveryPlan.t()
  def plan(source, mode) do
    {:ok, candidates} = Negotiation.candidates(source)
    candidate = Enum.find(candidates, &(&1.plan.mode == mode))
    %{candidate.plan | transport: :hls_js}
  end

  @spec negotiated_source(Source.t()) :: {Source.t(), DeliveryPlan.t()}
  def negotiated_source(source) do
    source = %{
      source
      | format: "matroska",
        tracks: [
          %TechnicalTrack{
            kind: :video,
            index: 3,
            codec: "h264",
            codec_string: "avc1.42C029",
            profile: "Constrained Baseline",
            level: 41,
            width: 320,
            height: 180,
            frame_rate: "24/1",
            bit_rate: 1_000_000,
            pixel_format: "yuv420p",
            bit_depth: 8,
            color_transfer: "bt709",
            color_primaries: "bt709",
            color_space: "bt709",
            attached_picture?: false,
            default?: true
          },
          %TechnicalTrack{
            kind: :audio,
            index: 7,
            codec: "aac",
            codec_string: "mp4a.40.2",
            profile: "LC",
            channels: 2,
            sample_rate: 48_000,
            bit_rate: 128_000,
            default?: true
          }
        ]
    }

    {:ok, candidates} = Negotiation.candidates(source)
    candidate = Enum.find(candidates, &(&1.plan.mode == :remux))
    {source, %{candidate.plan | transport: :hls_js}}
  end
end
