defmodule Bolognesa.Libraries.InspectionMetadataTest do
  use ExUnit.Case, async: true
  alias Bolognesa.Infrastructure.Persistence.InspectionSchema
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoInspectionRepository.InspectionMapper

  test "inspection JSON retains negotiation facts and legacy records remain readable" do
    row = %{
      "kind" => "video",
      "codec" => "h264",
      "index" => 3,
      "profile" => "High",
      "default?" => true,
      "attached_picture?" => false,
      "color_transfer" => "bt709"
    }

    inspection = InspectionMapper.to_inspection(%InspectionSchema{tracks: %{"items" => [row]}})
    track = hd(inspection.tracks)
    assert Map.get(track, :index) == 3
    assert Map.get(track, :profile) == "High"
    assert Map.get(track, :default?) == true
    assert Map.get(track, :attached_picture?) == false
    assert Map.get(track, :color_transfer) == "bt709"

    legacy =
      InspectionMapper.to_inspection(%InspectionSchema{
        tracks: %{"items" => [%{"kind" => "video", "codec" => "h264"}]}
      })

    assert hd(legacy.tracks).codec == "h264"
    assert Map.get(hd(legacy.tracks), :index) == nil
  end
end
