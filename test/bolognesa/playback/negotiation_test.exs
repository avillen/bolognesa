defmodule Bolognesa.Playback.NegotiationTest do
  use ExUnit.Case, async: true
  alias Bolognesa.Playback.Domain.Policies.Negotiation
  alias Bolognesa.Playback.Domain.ReadModels.{Source, TechnicalTrack}
  alias Bolognesa.Playback.Domain.ValueObjects.CapabilityReport

  test "selects the cheapest positively supported transformation with absolute indexes" do
    source = source()
    assert {:ok, candidates} = Negotiation.candidates(source)
    assert length(candidates) <= 6

    for {mode, expected} <- [
          direct: {:original, :original},
          remux: {:copy, :copy},
          audio_conversion: {:copy, :aac},
          video_conversion: {:h264, :copy},
          full_conversion: {:h264, :aac}
        ] do
      candidate = Enum.find(candidates, &(&1.plan.mode == mode))
      assert candidate
      report = report(candidates, candidate.id)
      assert {:ok, observations} = CapabilityReport.new(report, candidates, "generation")
      assert {:ok, plan} = Negotiation.select(source, candidates, observations)
      assert {plan.video_action, plan.audio_action} == expected
      assert plan.video_index == 3
      assert plan.audio_index == 7
      assert plan.revision == 2
    end

    assert {:ok, observations} =
             CapabilityReport.new(report(candidates, :all), candidates, "generation")

    assert {:ok, %{mode: :direct}} = Negotiation.select(source, candidates, observations)
  end

  test "compatible preference selects the verified full conversion envelope" do
    source = source()
    {:ok, candidates} = Negotiation.candidates(source)
    report = Map.put(report(candidates, :all), "preference", "compatible")
    {:ok, observations} = CapabilityReport.new(report, candidates, "generation")
    assert {:ok, plan} = Negotiation.select(source, candidates, observations)
    assert plan.mode == :full_conversion
    assert plan.configuration.video.codec_string == "avc1.42C029"
    assert plan.configuration.video.width == 1920
    assert plan.configuration.video.height == 1080
    assert plan.configuration.video.frame_rate == 30.0
    assert plan.configuration.video.bit_rate == 8_000_000
    assert plan.configuration.audio.codec_string == "mp4a.40.2"
    assert plan.configuration.audio.sample_rate == 48_000
    assert plan.configuration.audio.channels == 2
    assert plan.configuration.audio.bit_rate == 128_000
  end

  test "silent sources omit all audio actions and do not upscale" do
    source = source()
    [video, _audio] = source.tracks
    source = %{source | tracks: [%{video | width: 320, height: 180, frame_rate: "24/1"}]}
    {:ok, candidates} = Negotiation.candidates(source)
    assert Enum.all?(candidates, &is_nil(&1.plan.audio_index))
    full = Enum.find(candidates, &(&1.plan.video_action == :h264))
    assert full.plan.audio_action == :absent
    assert full.plan.configuration.audio == nil
    assert full.plan.configuration.video.width == 320
    assert full.plan.configuration.video.height == 180
    assert full.plan.configuration.video.frame_rate == 24.0
  end

  test "direct delivery requires unambiguous default tracks and excludes attached pictures" do
    source = source()
    [video, audio] = source.tracks
    alternate = %{audio | index: 9, default?: true}

    source = %{
      source
      | tracks: [
          alternate,
          %{audio | default?: false},
          video,
          %{video | index: 0, attached_picture?: true}
        ]
    }

    {:ok, candidates} = Negotiation.candidates(source)
    refute Enum.any?(candidates, &(&1.plan.mode == :direct))
    assert Enum.all?(candidates, &(&1.plan.video_index == 3 and &1.plan.audio_index == 7))
  end

  test "HDR can be probed directly but never produces an SDR conversion candidate" do
    source = source()
    [video, audio] = source.tracks
    source = %{source | tracks: [%{video | color_transfer: "smpte2084"}, audio]}
    assert {:ok, [candidate]} = Negotiation.candidates(source)
    assert candidate.plan.mode == :direct

    {:ok, observations} =
      CapabilityReport.new(report([candidate], nil), [candidate], "generation")

    assert {:error, :unsupported_conversion} =
             Negotiation.select(source, [candidate], observations)
  end

  test "unknown color facts or stream indexes never establish safe transformation" do
    source = source()
    [video, audio] = source.tracks

    for altered <- [%{video | color_transfer: nil}, %{video | profile: nil}] do
      source = %{source | tracks: [altered, audio]}
      assert {:ok, [candidate]} = Negotiation.candidates(source)
      assert candidate.plan.mode == :direct
      {:ok, report} = CapabilityReport.new(report([candidate], nil), [candidate], "generation")
      assert {:error, :metadata_required} = Negotiation.select(source, [candidate], report)
    end

    assert {:error, :metadata_required} =
             Negotiation.candidates(%{source | tracks: [%{video | index: nil}]})
  end

  test "HEVC video and multichannel AAC cannot be copied into the MPEG-TS envelope" do
    source = source()
    [video, audio] = source.tracks

    source = %{
      source
      | tracks: [
          %{video | codec: "hevc", codec_string: "hvc1.1.6.L93.B0"},
          %{audio | channels: 6}
        ]
    }

    {:ok, candidates} = Negotiation.candidates(source)
    assert Enum.map(candidates, & &1.plan.mode) == [:direct, :full_conversion]
  end

  test "missing reports remain unknown and never silently choose direct or conversion" do
    source = source()
    {:ok, candidates} = Negotiation.candidates(source)

    {:ok, report} =
      CapabilityReport.new(
        %{"version" => 1, "generation" => "generation", "preference" => "auto", "results" => []},
        candidates,
        "generation"
      )

    assert {:error, :detection_unknown} = Negotiation.select(source, candidates, report)
  end

  test "closed report contract rejects forged, duplicated or oversized payloads" do
    {:ok, candidates} = Negotiation.candidates(source())
    good = report(candidates, :all)
    result = hd(good["results"])

    bad_results = [
      Map.put(result, "candidate_id", "unissued"),
      Map.put(result, "transport", "file:///tmp/x"),
      Map.put(result, "support", "probably"),
      Map.put(result, "smooth", true),
      Map.put(result, "power_efficient", "supported"),
      Map.put(result, "codec", "h264"),
      Map.put(result, "candidate_id", String.duplicate("a", 65))
    ]

    invalid =
      [
        Map.put(good, "version", 2),
        Map.put(good, "extra", "x"),
        Map.put(good, "generation", "stale"),
        Map.put(good, "preference", "fast"),
        Map.put(good, "results", [result, result]),
        Map.put(good, "results", List.duplicate(result, 7)),
        Map.put(good, "generation", String.duplicate("a", 8193))
      ] ++ Enum.map(bad_results, &Map.put(good, "results", [&1]))

    for report <- invalid do
      assert {:error, :invalid_report} = CapabilityReport.new(report, candidates, "generation")
    end

    original = Enum.find(candidates, &(&1.plan.mode == :direct))
    contradictory = %{result | "candidate_id" => original.id, "transport" => "hls_js"}

    assert {:error, :invalid_report} =
             CapabilityReport.new(
               Map.put(good, "results", [contradictory]),
               candidates,
               "generation"
             )
  end

  test "unchanged source bindings and chosen transport are retained in the plan" do
    source = source()
    {:ok, candidates} = Negotiation.candidates(source)
    remux = Enum.find(candidates, &(&1.plan.mode == :remux))
    raw = report(candidates, remux.id)

    results =
      Enum.map(
        raw["results"],
        &Map.put(&1, "transport", if(&1["transport"] == "file", do: "file", else: "native_hls"))
      )

    {:ok, observations} =
      CapabilityReport.new(%{raw | "results" => results}, candidates, "generation")

    assert {:ok, %{mode: :remux, transport: :native_hls}} =
             Negotiation.select(source, candidates, observations)

    assert {:error, :source_changed} =
             Negotiation.select(%{source | revision: 3}, candidates, observations)
  end

  test "client rejection cannot widen the output envelope to unsupported profiles or rates" do
    source = source()
    [video, audio] = source.tracks

    for changed <- [
          %{video | profile: "High", codec_string: "avc1.640029"},
          %{video | level: 50},
          %{video | width: 3840, height: 2160},
          %{video | frame_rate: "60/1"},
          %{video | bit_depth: 10, pixel_format: "yuv420p10le"}
        ] do
      {:ok, candidates} = Negotiation.candidates(%{source | tracks: [changed, audio]})
      refute Enum.any?(candidates, &(&1.plan.video_action == :copy))
    end

    {:ok, candidates} = Negotiation.candidates(source)
    {:ok, observations} = CapabilityReport.new(report(candidates, nil), candidates, "generation")
    assert {:error, :unsupported} = Negotiation.select(source, candidates, observations)
    compatible = Map.put(report(candidates, "c0"), "preference", "compatible")
    {:ok, observations} = CapabilityReport.new(compatible, candidates, "generation")
    assert {:error, :unsupported} = Negotiation.select(source, candidates, observations)
  end

  test "unknown earlier video dispositions do not silently select a later video" do
    source = source()
    [video, audio] = source.tracks
    unknown = %{video | index: 0, attached_picture?: nil}

    assert {:error, :metadata_required} =
             Negotiation.candidates(%{source | tracks: [unknown, video, audio]})
  end

  test "unmapped subtitle facts do not prevent a controlled video and audio output" do
    source = source()
    subtitle = %TechnicalTrack{kind: :subtitle, index: nil, codec: "subrip"}
    {:ok, candidates} = Negotiation.candidates(%{source | tracks: [subtitle | source.tracks]})
    refute Enum.any?(candidates, &(&1.plan.mode == :direct))
    assert Enum.any?(candidates, &(&1.plan.mode == :remux))
  end

  defp source do
    %Source{
      revision: 2,
      format: "mov,mp4,m4a,3gp,3g2,mj2",
      tracks: [
        %TechnicalTrack{
          kind: :video,
          index: 3,
          codec: "h264",
          codec_string: "avc1.42C029",
          profile: "Constrained Baseline",
          level: 41,
          width: 1920,
          height: 1080,
          frame_rate: "30/1",
          bit_rate: 8_000_000,
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
  end

  defp report(candidates, supported) do
    %{
      "version" => 1,
      "generation" => "generation",
      "preference" => "auto",
      "results" =>
        Enum.map(candidates, fn candidate ->
          %{
            "candidate_id" => candidate.id,
            "transport" => if(candidate.plan.mode == :direct, do: "file", else: "hls_js"),
            "support" =>
              if(supported == :all or supported == candidate.id,
                do: "supported",
                else: "unsupported"
              ),
            "smooth" => "unknown",
            "power_efficient" => "unknown"
          }
        end)
    }
  end
end
