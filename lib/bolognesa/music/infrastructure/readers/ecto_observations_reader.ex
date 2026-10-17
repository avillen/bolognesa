defmodule Bolognesa.Music.Infrastructure.Readers.EctoObservationsReader do
  @moduledoc false
  @behaviour Bolognesa.Music.Application.Ports.Readers.ObservationsReader
  import Ecto.Query
  alias Bolognesa.Infrastructure.Persistence.{InspectionSchema, LibrarySchema, MediaFileSchema}
  alias Bolognesa.Music.Domain.ValueObjects.MusicTags
  alias Bolognesa.Music.Domain.ValueObjects.Observation
  alias Bolognesa.Repo
  @impl true
  def current(file_id, revision) do
    row =
      Repo.one(
        from(file in MediaFileSchema,
          join: library in LibrarySchema,
          on: library.id == file.library_id,
          join: inspection in InspectionSchema,
          on: inspection.media_file_id == file.id,
          where:
            file.id == ^file_id and file.revision == ^revision and file.availability == :available and
              library.content_type == :music and inspection.observed_revision == file.revision and
              inspection.state == :succeeded,
          select: {file, inspection}
        ),
        log: false
      )

    observation(row)
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp observation(nil), do: {:ok, :stale}

  defp observation({file, inspection}) do
    if Enum.any?(inspection.tracks["items"] || [], &(&1["kind"] == "audio")) do
      {:ok,
       %Observation{
         file_id: file.id,
         library_id: file.library_id,
         revision: file.revision,
         inspection_token: inspection.token,
         relative_path: file.relative_path,
         duration_ms: inspection.duration_ms,
         music_tags: tags(inspection.music_tags)
       }}
    else
      {:ok, :stale}
    end
  end

  defp tags(nil), do: %MusicTags{}

  defp tags(tags),
    do: %MusicTags{
      title: tags["title"],
      artist: tags["artist"],
      album_artist: tags["album_artist"],
      album: tags["album"],
      disc_number: tags["disc_number"],
      track_number: tags["track_number"],
      year: tags["year"]
    }
end
