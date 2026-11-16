defmodule Bolognesa.Playback.Domain.Policies.Negotiation do
  @moduledoc "Choose the least expensive positively tested, source-safe delivery."
  alias Bolognesa.Playback.Domain.ReadModels.Source
  alias Bolognesa.Playback.Domain.ReadModels.TechnicalTrack

  alias Bolognesa.Playback.Domain.ValueObjects.CapabilityReport
  alias Bolognesa.Playback.Domain.ValueObjects.DeliveryPlan
  alias Bolognesa.Playback.Domain.ValueObjects.MediaConfiguration
  alias Bolognesa.Playback.Domain.ValueObjects.PlaybackCandidate

  @type error ::
          :metadata_required
          | :no_video
          | :unsupported_conversion
          | :unsupported
          | :detection_unknown
          | :source_changed

  # HDR needs at least 10-bit samples, so 8-bit 4:2:0 video in these codecs is SDR by
  # construction even when it declares no color facts.
  @legacy_sdr_codecs ~w(mpeg4 msmpeg4v1 msmpeg4v2 msmpeg4v3 mpeg1video mpeg2video h263 flv1 wmv1 wmv2 wmv3 vc1)
  @sdr_transfers [nil, "bt709", "smpte170m", "bt470m", "bt470bg", "iec61966-2-1"]
  @sdr_primaries [nil, "bt709", "smpte170m", "bt470bg", "bt470m"]
  @sdr_matrices [nil, "bt709", "smpte170m", "bt470bg", "fcc"]
  @copy_sample_rates [32_000, 44_100, 48_000]
  @copy_aac_profiles ["LC", "HE-AAC"]
  @mp3_codec_string "mp4a.40.34"
  @max_output_frame_rate 30

  @spec candidates(Source.t()) ::
          {:ok, [PlaybackCandidate.t()]} | {:error, :metadata_required | :no_video}
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

      case preferred(supported, report) do
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
      if video, do: {:ok, video, audio}, else: {:error, :no_video}
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
      candidate(source, video, audio, %{
        id: "c0",
        mode: :direct,
        video_action: :original,
        audio_action: if(audio, do: :original, else: :absent),
        configuration: configuration(container, mime, video_config(video), audio_config(audio))
      })
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
    has_audio = not is_nil(audio)
    copy_audio = not has_audio or copy_audio?(audio)
    copied = %{video: video_config(video), audio: audio_config(audio)}
    encoded = %{video: encoded_video(video), audio: encoded_audio(audio)}
    copy_or_absent = if has_audio, do: :copy, else: :absent
    aac_or_absent = if has_audio, do: :aac, else: :absent

    [
      {copy_video and copy_audio, "c1", :remux, {:copy, copied}, {copy_or_absent, copied}},
      {copy_video and has_audio, "c2", :audio_conversion, {:copy, copied}, {:aac, encoded}},
      {encode_video and copy_audio, "c3", :video_conversion, {:h264, encoded},
       {copy_or_absent, copied}},
      {encode_video and has_audio, "c4", :full_conversion, {:h264, encoded},
       {aac_or_absent, encoded}}
    ]
    |> Enum.filter(&elem(&1, 0))
    |> Enum.map(fn {true, id, mode, {video_action, v}, {audio_action, a}} ->
      candidate(source, video, audio, %{
        id: id,
        mode: mode,
        video_action: video_action,
        audio_action: audio_action,
        configuration: configuration(:mpegts, "video/mp2t", v.video, a.audio)
      })
    end)
  end

  defp candidate(source, video, audio, option) do
    %PlaybackCandidate{
      id: option.id,
      transports: if(option.mode == :direct, do: [:file], else: [:hls_js, :native_hls]),
      plan: %DeliveryPlan{
        revision: source.revision,
        video_index: video.index,
        audio_index: if(audio, do: audio.index),
        mode: option.mode,
        video_action: option.video_action,
        audio_action: option.audio_action,
        configuration: option.configuration
      }
    }
  end

  defp configuration(container, mime, video, audio),
    do: %MediaConfiguration{container: container, mime: mime, video: video, audio: audio}

  # Container names as reported by ffprobe's format_name.
  defp original_container("mov,mp4,m4a,3gp,3g2,mj2"), do: {:ok, :mp4, "video/mp4"}
  defp original_container("matroska,webm"), do: {:ok, :matroska, "video/x-matroska"}
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

  defp safe_sdr?(video), do: known_color_facts?(video) or implied_sdr?(video)

  defp known_color_facts?(video) do
    video.profile != nil and video.pixel_format != nil and video.bit_depth in 8..16 and
      video.color_transfer != nil and video.color_primaries != nil and video.color_space != nil and
      sdr_color_facts?(video)
  end

  # Present declarations must still be SDR-safe; absent ones are SDR by construction here.
  defp implied_sdr?(video) do
    video.pixel_format == "yuv420p" and video.bit_depth == 8 and sdr_color_facts?(video) and
      (video.codec in @legacy_sdr_codecs or (video.codec == "h264" and video.profile != nil))
  end

  # Copy preserves absent color declarations; only explicit unsupported values exclude it.
  defp sdr_color_facts?(video) do
    video.color_transfer in @sdr_transfers and video.color_primaries in @sdr_primaries and
      video.color_space in @sdr_matrices
  end

  defp complete_video?(video),
    do:
      is_integer(video.width) and video.width > 0 and is_integer(video.height) and
        video.height > 0 and is_number(frame_rate(video.frame_rate))

  defp copy_video?(video),
    do: sdr_color_facts?(video) and copy_video_format?(video) and copy_video_bounds?(video)

  defp copy_video_format?(video) do
    exact_codec?(video) and video.codec == "h264" and video.pixel_format == "yuv420p" and
      video.bit_depth == 8 and video.profile in ["Constrained Baseline", "Main", "High"] and
      video.level in 1..41
  end

  defp copy_video_bounds?(video) do
    video.width <= 1920 and video.height <= 1080 and
      frame_rate(video.frame_rate) <= @max_output_frame_rate and
      (is_nil(video.bit_rate) or video.bit_rate <= 8_000_000)
  end

  # The browser still has to confirm each copied configuration; anything else becomes AAC-LC.
  defp copy_audio?(%TechnicalTrack{codec: "aac"} = audio),
    do: exact_codec?(audio) and audio.profile in @copy_aac_profiles and copy_audio_layout?(audio)

  defp copy_audio?(%TechnicalTrack{codec: "mp3"} = audio), do: copy_audio_layout?(audio)
  defp copy_audio?(_), do: false

  defp copy_audio_layout?(audio),
    do: audio.channels in [1, 2] and audio.sample_rate in @copy_sample_rates

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
      codec_string: audio_codec_string(audio),
      sample_rate: audio.sample_rate,
      channels: audio.channels,
      bit_rate: audio.bit_rate
    }

  defp audio_codec_string(%TechnicalTrack{codec: "mp3"}), do: @mp3_codec_string
  defp audio_codec_string(audio), do: audio.codec_string

  defp encoded_audio(nil), do: nil

  defp encoded_audio(_),
    do: %{codec_string: "mp4a.40.2", sample_rate: 48_000, channels: 2, bit_rate: 128_000}

  defp encoded_video(video) do
    scale = min(1.0, min(1920 / video.width, 1080 / video.height))

    %{
      codec_string: "avc1.42C029",
      width: max(2, trunc(video.width * scale / 2) * 2),
      height: max(2, trunc(video.height * scale / 2) * 2),
      frame_rate: output_frame_rate(frame_rate(video.frame_rate)),
      bit_rate: 8_000_000
    }
  end

  # Dropping frames by an integer divisor keeps motion even (50 -> 25, 59.94 -> 29.97).
  defp output_frame_rate(rate) when rate <= @max_output_frame_rate, do: rate / 1

  defp output_frame_rate(rate),
    do: rate / Float.ceil(rate / @max_output_frame_rate)

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

  # Candidates are ordered by server cost; a browser that predicts stutter yields to the next.
  defp preferred(candidates, %CapabilityReport{preference: :auto} = report),
    do: Enum.find(candidates, &(not stutters?(&1, report))) || List.first(candidates)

  # Compatible recovery replaces a failed delivery, so it never falls back to another envelope.
  defp preferred(candidates, %CapabilityReport{preference: :compatible}),
    do:
      Enum.find(
        candidates,
        &(&1.plan.video_action == :h264 and &1.plan.audio_action in [:aac, :absent])
      )

  defp stutters?(candidate, report),
    do: match?(%{smooth: :no}, Map.get(report.results, candidate.id))

  defp rejection(source, report) do
    {:ok, video, _audio} = selected_tracks(source.tracks)

    cond do
      # Declared HDR, BT.2020 or RGB facts are known; they are unsupported, not missing.
      not sdr_color_facts?(video) ->
        {:error, :unsupported_conversion}

      Enum.all?(report.results, fn {_id, result} -> result.support == :unknown end) ->
        {:error, :detection_unknown}

      not safe_sdr?(video) or not complete_video?(video) ->
        {:error, :metadata_required}

      true ->
        {:error, :unsupported}
    end
  end
end
