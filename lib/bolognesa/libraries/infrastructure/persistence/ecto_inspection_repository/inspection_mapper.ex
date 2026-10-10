defmodule Bolognesa.Libraries.Infrastructure.Persistence.EctoInspectionRepository.InspectionMapper do
  @moduledoc false

  alias Bolognesa.Libraries.Domain.{Inspection, TechnicalTrack}
  alias Bolognesa.Persistence.InspectionSchema

  @spec to_inspection(InspectionSchema.t()) :: Inspection.t()
  def to_inspection(schema) do
    %Inspection{
      media_file_id: schema.media_file_id,
      token: schema.token,
      observed_revision: schema.observed_revision,
      state: schema.state,
      failure_reason: schema.failure_reason,
      job_id: schema.job_id,
      format: schema.format,
      duration_ms: schema.duration_ms,
      tracks: Enum.map(schema.tracks["items"] || [], &to_track/1)
    }
  end

  defp to_track(row) do
    %TechnicalTrack{
      kind: track_kind(row["kind"]),
      codec: row["codec"],
      width: row["width"],
      height: row["height"],
      channels: row["channels"],
      language: row["language"]
    }
  end

  defp track_kind("video"), do: :video
  defp track_kind("audio"), do: :audio
  defp track_kind("subtitle"), do: :subtitle
end
