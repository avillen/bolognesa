defmodule Bolognesa.Playback.NegotiationTest do
  use ExUnit.Case, async: true
  alias Bolognesa.Playback.Domain.Policies.Negotiation
  alias Bolognesa.Playback.Domain.ReadModels.Source
  alias Bolognesa.Playback.Domain.ReadModels.TechnicalTrack
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

  test "Matroska streams can be copied without inventing missing average bitrates" do
    source = source()
    [video, audio] = source.tracks

    source = %{
      source
      | format: "matroska,webm",
        tracks: [
          %{video | bit_rate: nil},
          %{audio | bit_rate: nil}
        ]
    }

    assert {:ok, candidates} = Negotiation.candidates(source)
    candidate = Enum.find(candidates, &(&1.plan.mode == :remux))
    assert candidate

    {:ok, observations} =
      CapabilityReport.new(report(candidates, candidate.id), candidates, "generation")

    assert {:ok, plan} = Negotiation.select(source, candidates, observations)
    assert plan.video_action == :copy
    assert plan.audio_action == :copy
    assert is_nil(plan.configuration.video.bit_rate)
    assert is_nil(plan.configuration.audio.bit_rate)
  end

  test "High video is copied while surround E-AC-3 becomes AAC instead of re-encoding video" do
    source = source()
    [video, audio] = source.tracks

    source = %{
      source
      | format: "matroska,webm",
        tracks: [
          %{
            video
            | profile: "High",
              level: 40,
              codec_string: "avc1.640028",
              width: 1920,
              height: 960,
              frame_rate: "24000/1001",
              bit_rate: nil
          },
          %{audio | codec: "eac3", codec_string: nil, profile: nil, channels: 6}
        ]
    }

    assert {:ok, candidates} = Negotiation.candidates(source)
    copy = Enum.find(candidates, &(&1.plan.mode == :audio_conversion))
    assert copy.plan.video_action == :copy
    assert copy.plan.configuration.video.codec_string == "avc1.640028"

    refute Enum.any?(candidates, &(&1.plan.mode == :direct))

    {:ok, observations} =
      CapabilityReport.new(report(candidates, copy.id), candidates, "generation")

    assert {:ok, plan} = Negotiation.select(source, candidates, observations)
    assert {plan.video_action, plan.audio_action} == {:copy, :aac}
    assert :ok = Negotiation.validate_plan(source, plan)
  end

  test "Main video with unknown color facts is preserved before converting while AC-3 becomes AAC" do
    source = source()
    [video, audio] = source.tracks

    for {level, codec_string, width, height, rate} <- [
          {31, "avc1.4D401F", 1280, 720, "25/1"},
          {41, "avc1.4D4029", 1920, 1080, "30/1"}
        ] do
      source = %{
        source
        | format: "matroska,webm",
          tracks: [
            %{
              video
              | profile: "Main",
                level: level,
                codec_string: codec_string,
                width: width,
                height: height,
                frame_rate: rate,
                bit_rate: nil,
                color_transfer: nil,
                color_primaries: nil,
                color_space: nil
            },
            %{audio | codec: "ac3", codec_string: nil, profile: nil, sample_rate: 48_000}
          ]
      }

      assert {:ok, [candidate, fallback]} = Negotiation.candidates(source)
      assert candidate.plan.mode == :audio_conversion
      assert fallback.plan.mode == :full_conversion
      assert candidate.plan.video_action == :copy
      assert candidate.plan.audio_action == :aac
      assert candidate.plan.configuration.video.codec_string == codec_string
      assert candidate.plan.configuration.video.bit_rate == nil
      assert candidate.plan.configuration.audio.codec_string == "mp4a.40.2"

      issued = [candidate, fallback]

      {:ok, observations} =
        CapabilityReport.new(report(issued, :all), issued, "generation")

      assert {:ok, plan} = Negotiation.select(source, issued, observations)
      assert plan.mode == :audio_conversion
      assert :ok = Negotiation.validate_plan(source, plan)

      {:ok, rejected} = CapabilityReport.new(report(issued, nil), issued, "generation")
      refute match?({:ok, _}, Negotiation.select(source, issued, rejected))
    end
  end

  test "absent color facts on 8-bit 4:2:0 H.264 imply SDR and allow every delivery" do
    source = source()
    [video, audio] = source.tracks

    for changed <- [
          %{video | color_transfer: nil},
          %{video | color_primaries: nil},
          %{video | color_space: nil},
          %{video | color_transfer: nil, color_primaries: nil, color_space: nil}
        ] do
      assert {:ok, candidates} = Negotiation.candidates(%{source | tracks: [changed, audio]})

      assert Enum.map(candidates, & &1.plan.mode) ==
               [:direct, :remux, :audio_conversion, :video_conversion, :full_conversion]
    end
  end

  test "absent color facts never establish encoding for high bit depth or modern codecs" do
    source = source()
    [video, audio] = source.tracks
    untagged = %{video | color_transfer: nil, color_primaries: nil, color_space: nil}

    for changed <- [
          %{untagged | pixel_format: "yuv420p10le", bit_depth: 10, profile: "High 10"},
          %{untagged | codec: "hevc", codec_string: "hvc1.1.6.L120.90", profile: "Main"},
          %{untagged | codec: "vp9", codec_string: nil, profile: "Profile 0"},
          %{untagged | profile: nil}
        ] do
      result = Negotiation.candidates(%{source | tracks: [changed, audio]})
      modes = with {:ok, candidates} <- result, do: Enum.map(candidates, & &1.plan.mode)
      refute is_list(modes) and Enum.any?(modes, &(&1 in [:video_conversion, :full_conversion]))
    end
  end

  test "untagged Xvid AVI with MP3 is converted instead of requiring metadata" do
    source = %Source{
      revision: 1,
      format: "avi",
      tracks: [
        %TechnicalTrack{
          kind: :video,
          index: 0,
          codec: "mpeg4",
          profile: "Simple Profile",
          level: 3,
          width: 720,
          height: 404,
          frame_rate: "24/1",
          bit_rate: 1_999_458,
          pixel_format: "yuv420p",
          bit_depth: 8,
          attached_picture?: false,
          default?: false
        },
        %TechnicalTrack{
          kind: :audio,
          index: 1,
          codec: "mp3",
          channels: 2,
          sample_rate: 44_100,
          bit_rate: 128_000,
          default?: false
        }
      ]
    }

    assert {:ok, [copied_audio, candidate] = issued} = Negotiation.candidates(source)
    assert copied_audio.plan.mode == :video_conversion
    assert {copied_audio.plan.video_action, copied_audio.plan.audio_action} == {:h264, :copy}
    assert copied_audio.plan.configuration.audio.codec_string == "mp4a.40.34"
    assert candidate.plan.mode == :full_conversion
    assert {candidate.plan.video_action, candidate.plan.audio_action} == {:h264, :aac}
    assert candidate.plan.configuration.video.width == 720
    assert candidate.plan.configuration.video.height == 404

    {:ok, observations} =
      CapabilityReport.new(report(issued, candidate.id), issued, "generation")

    assert {:ok, %{mode: :full_conversion}} = Negotiation.select(source, issued, observations)

    assert {:error, :metadata_required} =
             Negotiation.candidates(%{
               source
               | tracks: [%{hd(source.tracks) | bit_depth: 10, pixel_format: "yuv420p10le"}]
             })
  end

  test "explicit unsupported color facts still prevent copying" do
    source = source()
    [video, audio] = source.tracks

    for changed <- [
          %{video | color_transfer: "arib-std-b67"},
          %{video | color_primaries: "bt2020", color_transfer: nil},
          %{video | color_space: "bt2020nc", color_transfer: nil}
        ] do
      assert {:ok, [candidate]} = Negotiation.candidates(%{source | tracks: [changed, audio]})
      assert candidate.plan.mode == :direct
    end
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

  test "unknown profile or stream indexes never establish safe transformation" do
    source = source()
    [video, audio] = source.tracks

    for altered <- [%{video | profile: nil}, %{video | bit_depth: nil}] do
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
          %{video | profile: "High 4:2:2", codec_string: "avc1.7A0029"},
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

  test "declared non-SDR color facts are unsupported instead of missing" do
    source = source()
    [video, audio] = source.tracks

    for changed <- [
          %{video | color_primaries: "bt2020"},
          %{video | color_space: "bt2020nc"},
          %{video | color_space: "gbr"},
          %{video | color_transfer: "smpte2084"}
        ] do
      source = %{source | tracks: [changed, audio]}
      assert {:ok, [candidate]} = Negotiation.candidates(source)
      assert candidate.plan.mode == :direct
      {:ok, rejected} = CapabilityReport.new(report([candidate], nil), [candidate], "generation")

      assert {:error, :unsupported_conversion} =
               Negotiation.select(source, [candidate], rejected)
    end
  end

  test "undetectable browsers are reported before missing technical facts" do
    source = source()
    [video, audio] = source.tracks
    source = %{source | tracks: [%{video | profile: nil}, audio]}
    assert {:ok, [candidate]} = Negotiation.candidates(source)

    {:ok, unknown} =
      CapabilityReport.new(report([candidate], :unknown), [candidate], "generation")

    assert {:error, :detection_unknown} = Negotiation.select(source, [candidate], unknown)
  end

  test "ffprobe names for SD gamma transfers are SDR for copy and encoding" do
    source = source()
    [video, audio] = source.tracks

    for transfer <- ["bt470bg", "bt470m"] do
      changed = %{video | color_transfer: transfer, color_primaries: "bt470bg"}
      assert {:ok, candidates} = Negotiation.candidates(%{source | tracks: [changed, audio]})
      modes = Enum.map(candidates, & &1.plan.mode)
      assert :remux in modes
      assert :full_conversion in modes
    end
  end

  test "high frame rates are encoded at an even integer divisor" do
    source = source()
    [video, audio] = source.tracks

    for {rate, expected} <- [
          {"50/1", 25.0},
          {"60000/1001", 60_000 / 1001 / 2},
          {"120/1", 30.0},
          {"48/1", 24.0},
          {"30000/1001", 30_000 / 1001},
          {"24/1", 24.0}
        ] do
      changed = %{video | frame_rate: rate}
      assert {:ok, candidates} = Negotiation.candidates(%{source | tracks: [changed, audio]})
      full = Enum.find(candidates, &(&1.plan.mode == :full_conversion))
      assert_in_delta full.plan.configuration.video.frame_rate, expected, 0.0001
    end
  end

  test "automatic preference skips candidates the browser predicts will stutter" do
    source = source()
    {:ok, candidates} = Negotiation.candidates(source)
    raw = report(candidates, :all)

    stutter = fn raw, ids ->
      Map.update!(raw, "results", fn results ->
        Enum.map(results, &if(&1["candidate_id"] in ids, do: %{&1 | "smooth" => "no"}, else: &1))
      end)
    end

    {:ok, observations} =
      CapabilityReport.new(stutter.(raw, ["c0", "c1"]), candidates, "generation")

    assert {:ok, %{mode: :audio_conversion}} =
             Negotiation.select(source, candidates, observations)

    all_ids = Enum.map(candidates, & &1.id)
    {:ok, observations} = CapabilityReport.new(stutter.(raw, all_ids), candidates, "generation")
    assert {:ok, %{mode: :direct}} = Negotiation.select(source, candidates, observations)
  end

  test "browser-verified HE-AAC and stereo MP3 are copied while other audio becomes AAC" do
    source = source()
    [video, audio] = source.tracks

    for {changed, copied?, codec_string} <- [
          {%{audio | profile: "HE-AAC"}, true, "mp4a.40.2"},
          {%{audio | profile: "HE-AACv2", codec_string: nil}, false, nil},
          {%{audio | codec: "mp3", codec_string: nil, profile: nil}, true, "mp4a.40.34"},
          {%{audio | codec: "mp3", codec_string: nil, profile: nil, sample_rate: 22_050}, false,
           nil},
          {%{audio | codec: "mp3", codec_string: nil, profile: nil, channels: 6}, false, nil},
          {%{audio | codec: "ac3", codec_string: nil, profile: nil}, false, nil}
        ] do
      assert {:ok, candidates} = Negotiation.candidates(%{source | tracks: [video, changed]})
      remux = Enum.find(candidates, &(&1.plan.mode == :remux))
      assert Enum.any?(candidates, &(&1.plan.mode == :full_conversion))

      if copied? do
        assert remux.plan.audio_action == :copy
        assert remux.plan.configuration.audio.codec_string == codec_string
      else
        refute remux
      end
    end
  end

  test "sources without a playable video track report no video" do
    source = source()
    [video, audio] = source.tracks
    assert {:error, :no_video} = Negotiation.candidates(%{source | tracks: [audio]})

    assert {:error, :no_video} =
             Negotiation.candidates(%{
               source
               | tracks: [%{video | attached_picture?: true}, audio]
             })
  end

  test "direct delivery only trusts container names reported by ffprobe" do
    source = source()
    assert {:ok, [%{plan: %{mode: :direct}} | _]} = Negotiation.candidates(source)

    for format <- ["mp4", "mov", "webm", "avi"] do
      assert {:ok, candidates} = Negotiation.candidates(%{source | format: format})
      refute Enum.any?(candidates, &(&1.plan.mode == :direct))
    end

    assert {:ok, [%{plan: %{mode: :direct, configuration: %{container: :matroska}}} | _]} =
             Negotiation.candidates(%{source | format: "matroska,webm"})
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
              cond do
                supported == :unknown -> "unknown"
                supported == :all or supported == candidate.id -> "supported"
                true -> "unsupported"
              end,
            "smooth" => "unknown",
            "power_efficient" => "unknown"
          }
        end)
    }
  end
end
