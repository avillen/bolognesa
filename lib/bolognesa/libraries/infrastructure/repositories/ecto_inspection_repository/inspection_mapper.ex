defmodule Bolognesa.Libraries.Infrastructure.Repositories.EctoInspectionRepository.InspectionMapper do
  @moduledoc false

  alias Bolognesa.Infrastructure.Persistence.InspectionSchema
  alias Bolognesa.Libraries.Domain.Entities.Inspection
  alias Bolognesa.Libraries.Domain.ValueObjects.Inspection.{MusicTags, TechnicalTrack}

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
      music_tags: music_tags(schema.music_tags),
      tracks: Enum.map(schema.tracks["items"] || [], &to_track/1)
    }
  end

  defp music_tags(nil), do: nil

  defp music_tags(tags) do
    %MusicTags{
      title: tags["title"],
      artist: tags["artist"],
      album: tags["album"],
      album_artist: tags["album_artist"],
      disc_number: tags["disc_number"],
      track_number: tags["track_number"],
      year: tags["year"]
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
