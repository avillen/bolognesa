defmodule Bolognesa.Playback.Domain.Policies.Negotiation do
  @moduledoc "Choose the least expensive positively tested, source-safe delivery."
  alias Bolognesa.Playback.Domain.ReadModels.{Source, TechnicalTrack}

  alias Bolognesa.Playback.Domain.ValueObjects.{
    CapabilityReport,
    DeliveryPlan,
    MediaConfiguration,
    PlaybackCandidate
  }

  @type error ::
          :metadata_required
          | :unsupported_conversion
          | :unsupported
          | :detection_unknown
          | :source_changed

  @spec candidates(Source.t()) :: {:ok, [PlaybackCandidate.t()]} | {:error, :metadata_required}
  def candidates(%Source{revision: revision} = source)
      when is_integer(revision) and revision > 0 do
    with {:ok, video, audio} <- selected_tracks(source.tracks) do
      direct = direct_candidate(source, video, audio)
      transformed = transformed_candidates(source, video, audio)
      candidates = Enum.reject([direct | transformed], &is_nil/1)
      if candidates == [], do: {:error, :metadata_required}, else: {:ok, candidates}
    end
  end

  def candidates(_), do: {:error, :metadata_required}

  @spec select(Source.t(), [PlaybackCandidate.t()], CapabilityReport.t()) ::
          {:ok, DeliveryPlan.t()} | {:error, error()}
  def select(source, issued, %CapabilityReport{} = report) do
    with {:ok, current} <- candidates(source),
         true <- current == issued do
      supported = Enum.filter(issued, &supported?(&1, report))

      case preferred(supported, report.preference) do
        nil ->
          rejection(source, report)

        candidate ->
          {:ok, %{candidate.plan | transport: Map.fetch!(report.results, candidate.id).transport}}
      end
    else
      _ -> {:error, :source_changed}
    end
  end

  @spec validate_plan(Source.t(), DeliveryPlan.t()) ::
          :ok | {:error, :source_changed | :unsupported}
  def validate_plan(%Source{revision: revision}, %DeliveryPlan{revision: expected})
      when revision != expected,
      do: {:error, :source_changed}

  def validate_plan(source, %DeliveryPlan{} = plan) do
    with {:ok, candidates} <- candidates(source),
         true <-
           Enum.any?(
             candidates,
             &(&1.plan == %{plan | transport: nil} and plan.transport in &1.transports)
           ) do
      :ok
    else
      _ -> {:error, :unsupported}
    end
  end

  defp selected_tracks(tracks) do
    media_tracks = Enum.filter(tracks, &(&1.kind in [:video, :audio]))

    if Enum.all?(media_tracks, &valid_index?/1) and unique_indexes?(media_tracks) and
         Enum.all?(media_tracks, &known_picture_disposition?/1) do
      sorted = Enum.sort_by(media_tracks, & &1.index)
      video = Enum.find(sorted, &(&1.kind == :video and &1.attached_picture? == false))
      audio = Enum.find(sorted, &(&1.kind == :audio))
      if video, do: {:ok, video, audio}, else: {:error, :metadata_required}
    else
      {:error, :metadata_required}
    end
  end

  defp known_picture_disposition?(%TechnicalTrack{kind: :video, attached_picture?: value}),
    do: is_boolean(value)

  defp known_picture_disposition?(_), do: true

  defp valid_index?(%TechnicalTrack{index: index}), do: is_integer(index) and index in 0..65_535
  defp unique_indexes?(tracks), do: length(Enum.uniq_by(tracks, & &1.index)) == length(tracks)

  defp direct_candidate(source, video, audio) do
    with true <- unambiguous_defaults?(source.tracks, video, audio),
         {:ok, container, mime} <- original_container(source.format),
         true <- exact_codec?(video) and (is_nil(audio) or exact_codec?(audio)) do
      config = configuration(container, mime, video_config(video), audio_config(audio))

      candidate(
        "c0",
        source,
        video,
        audio,
        :direct,
        :original,
        if(audio, do: :original, else: :absent),
        config
      )
    else
      _ -> nil
    end
  end

  defp unambiguous_defaults?(tracks, video, audio) do
    # Additional tracks may be selected by native players and are not covered by a single probe.
    selected = Enum.reject([video, audio], &is_nil/1)
    length(tracks) == length(selected) and Enum.all?(selected, &(&1.default? in [true, false]))
  end

  defp transformed_candidates(source, video, audio) do
    if complete_video?(video), do: build_transformed_candidates(source, video, audio), else: []
  end

  defp build_transformed_candidates(source, video, audio) do
    copy_video = copy_video?(video)
    encode_video = safe_sdr?(video)
    copy_audio = is_nil(audio) or copy_audio?(audio)
    copied_video = video_config(video)
    encoded_video = encoded_video(video)
    copied_audio = audio_config(audio)
    encoded_audio = encoded_audio(audio)
    absent_or_copy = if audio, do: :copy, else: :absent
    absent_or_aac = if audio, do: :aac, else: :absent

    options = [
      {copy_video and copy_audio, "c1", :remux, :copy, absent_or_copy, copied_video,
       copied_audio},
      {copy_video and not is_nil(audio), "c2", :audio_conversion, :copy, :aac, copied_video,
       encoded_audio},
      {encode_video and copy_audio, "c3", :video_conversion, :h264, absent_or_copy, encoded_video,
       copied_audio},
      {encode_video and not is_nil(audio), "c4", :full_conversion, :h264, absent_or_aac,
       encoded_video, encoded_audio}
    ]

    for {true, id, mode, video_action, audio_action, v, a} <- options do
      candidate(
        id,
        source,
        video,
        audio,
        mode,
        video_action,
        audio_action,
        configuration(:mpegts, "video/mp2t", v, a)
      )
    end
  end

  defp candidate(id, source, video, audio, mode, video_action, audio_action, config) do
    %PlaybackCandidate{
      id: id,
      transports: if(mode == :direct, do: [:file], else: [:hls_js, :native_hls]),
      plan: %DeliveryPlan{
        revision: source.revision,
        video_index: video.index,
        audio_index: if(audio, do: audio.index),
        mode: mode,
        video_action: video_action,
        audio_action: audio_action,
        configuration: config,
        reason: reason(mode)
      }
    }
  end

  defp reason(:direct), do: :original_supported
  defp reason(:remux), do: :remux_supported
  defp reason(:audio_conversion), do: :audio_conversion_required
  defp reason(:video_conversion), do: :video_conversion_required
  defp reason(:full_conversion), do: :full_conversion_required

  defp configuration(container, mime, video, audio),
    do: %MediaConfiguration{container: container, mime: mime, video: video, audio: audio}

  defp original_container(format) when format in ["mov,mp4,m4a,3gp,3g2,mj2", "mp4", "mov"],
    do: {:ok, :mp4, "video/mp4"}

  defp original_container("webm"), do: {:ok, :webm, "video/webm"}

  defp original_container(format) when format in ["matroska", "matroska,webm"],
    do: {:ok, :matroska, "video/x-matroska"}

  defp original_container(_), do: :error

  defp exact_codec?(%TechnicalTrack{codec: "h264", codec_string: value}) when is_binary(value),
    do: Regex.match?(~r/^avc1\.[0-9A-F]{6}$/, value)

  defp exact_codec?(%TechnicalTrack{codec: "hevc", codec_string: value}) when is_binary(value),
    do:
      Regex.match?(
        ~r/^(hvc1|hev1)\.[ABC]?[0-9]{1,2}\.[0-9A-F]{1,8}\.[LH][0-9]{1,3}(\.[0-9A-F]{2}){0,6}$/,
        value
      )

  defp exact_codec?(%TechnicalTrack{codec: "aac", codec_string: "mp4a.40.2"}), do: true
  defp exact_codec?(_), do: false

  defp safe_sdr?(video) do
    video.profile != nil and video.pixel_format != nil and video.bit_depth in 8..16 and
      video.color_transfer != nil and video.color_primaries != nil and video.color_space != nil and
      copy_color_facts?(video)
  end

  # Copy preserves absent color declarations; it does not infer SDR for video encoding.
  defp copy_color_facts?(video) do
    video.color_transfer in [nil, "bt709", "smpte170m", "gamma22", "gamma28", "iec61966-2-1"] and
      video.color_primaries in [nil, "bt709", "smpte170m", "bt470bg", "bt470m"] and
      video.color_space in [nil, "bt709", "smpte170m", "bt470bg", "fcc"]
  end

  defp complete_video?(video),
    do:
      is_integer(video.width) and video.width > 0 and is_integer(video.height) and
        video.height > 0 and is_number(frame_rate(video.frame_rate))

  defp copy_video?(video),
    do: copy_color_facts?(video) and copy_video_format?(video) and copy_video_bounds?(video)

  defp copy_video_format?(video) do
    video.codec == "h264" and exact_codec?(video) and video.pixel_format == "yuv420p" and
      video.bit_depth == 8 and video.profile in ["Constrained Baseline", "Main"] and
      video.level in 1..41
  end

  defp copy_video_bounds?(video) do
    video.width <= 1920 and video.height <= 1080 and frame_rate(video.frame_rate) <= 30 and
      (is_nil(video.bit_rate) or video.bit_rate <= 8_000_000)
  end

  defp copy_audio?(audio),
    do:
      audio.codec == "aac" and exact_codec?(audio) and audio.profile == "LC" and
        audio.channels in [1, 2] and audio.sample_rate in [32_000, 44_100, 48_000]

  defp video_config(video),
    do: %{
      codec_string: video.codec_string,
      width: video.width,
      height: video.height,
      frame_rate: frame_rate(video.frame_rate),
      bit_rate: video.bit_rate
    }

  defp audio_config(nil), do: nil

  defp audio_config(audio),
    do: %{
      codec_string: audio.codec_string,
      sample_rate: audio.sample_rate,
      channels: audio.channels,
      bit_rate: audio.bit_rate
    }

  defp encoded_audio(nil), do: nil

  defp encoded_audio(_),
    do: %{codec_string: "mp4a.40.2", sample_rate: 48_000, channels: 2, bit_rate: 128_000}

  defp encoded_video(video) do
    scale = min(1.0, min(1920 / video.width, 1080 / video.height))

    %{
      codec_string: "avc1.42C029",
      width: max(2, trunc(video.width * scale / 2) * 2),
      height: max(2, trunc(video.height * scale / 2) * 2),
      frame_rate: min(30.0, frame_rate(video.frame_rate)),
      bit_rate: 8_000_000
    }
  end

  defp frame_rate(rate) when is_binary(rate) do
    with [n, d] <- String.split(rate, "/"),
         {n, ""} <- Integer.parse(n),
         {d, ""} <- Integer.parse(d),
         true <- n > 0 and d > 0,
         do: n / d,
         else: (_ -> nil)
  end

  defp frame_rate(_), do: nil

  defp supported?(candidate, report),
    do: match?(%{support: :supported}, Map.get(report.results, candidate.id))

  defp preferred(candidates, :auto), do: List.first(candidates)

  defp preferred(candidates, :compatible),
    do:
      Enum.find(
        candidates,
        &(&1.plan.video_action == :h264 and &1.plan.audio_action in [:aac, :absent])
      )

  defp rejection(source, report) do
    {:ok, video, _audio} = selected_tracks(source.tracks)

    cond do
      video.color_transfer in ["smpte2084", "arib-std-b67"] ->
        {:error, :unsupported_conversion}

      not safe_sdr?(video) or not complete_video?(video) ->
        {:error, :metadata_required}

      Enum.all?(report.results, fn {_id, result} -> result.support == :unknown end) ->
        {:error, :detection_unknown}

      true ->
        {:error, :unsupported}
    end
  end
end
