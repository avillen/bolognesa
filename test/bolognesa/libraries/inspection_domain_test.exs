defmodule Bolognesa.Libraries.InspectionDomainTest do
  use ExUnit.Case, async: true

  alias Bolognesa.Libraries.Domain.Entities.{Inspection, MediaFile}
  alias Bolognesa.Libraries.Domain.ValueObjects.Files.NewMediaFile
  alias Bolognesa.Libraries.Domain.ValueObjects.Inspection.TechnicalMedia

  @modified ~U[2026-10-05 00:00:00Z]

  test "requests analysis for new, uninspected, changed, restored and forced files" do
    entry = entry(5)
    file = file()

    assert Inspection.request?(nil, false, entry, false)
    assert Inspection.request?(file, false, entry, false)
    assert Inspection.request?(file, true, entry(6), false)
    assert Inspection.request?(%{file | availability: :missing}, true, entry, false)
    assert Inspection.request?(file, true, entry, true)
    refute Inspection.request?(file, true, entry, false)
  end

  test "normalizes bounded technical data and rejects invalid values" do
    attrs = %{
      format: "matroska",
      duration_ms: 2_500,
      tracks: [
        %{kind: :video, codec: "h264", width: 1920, height: 1080},
        %{kind: :audio, codec: "aac", channels: 2, language: "es"}
      ]
    }

    assert {:ok, media} = TechnicalMedia.new(attrs)
    assert media.duration_ms == 2_500
    assert Enum.map(media.tracks, & &1.kind) == [:video, :audio]
    assert {:error, :invalid_data} = TechnicalMedia.new(%{attrs | duration_ms: -1})

    assert {:error, :invalid_data} =
             TechnicalMedia.new(%{attrs | tracks: [%{kind: :video, codec: ""}]})

    assert {:error, :invalid_data} =
             TechnicalMedia.new(%{attrs | tracks: List.duplicate(hd(attrs.tracks), 129)})
  end

  defp entry(size) do
    {:ok, value} =
      NewMediaFile.new(%{relative_path: "a.mp4", size_bytes: size, modified_at: @modified})

    value
  end

  defp file do
    %MediaFile{
      id: 1,
      library_id: 1,
      relative_path: "a.mp4",
      size_bytes: 5,
      modified_at: @modified,
      availability: :available,
      revision: 1,
      last_seen_generation: "e2a29409-26f6-4601-937f-b48f176db803"
    }
  end
end
