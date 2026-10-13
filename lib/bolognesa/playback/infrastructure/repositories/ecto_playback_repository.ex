defmodule Bolognesa.Playback.Infrastructure.Repositories.EctoPlaybackRepository do
  @moduledoc false
  @behaviour Bolognesa.Playback.Application.Ports.Repositories.PlaybackRepository

  import Ecto.Query

  alias Bolognesa.Infrastructure.Persistence.CatalogEntrySchema
  alias Bolognesa.Infrastructure.Persistence.IdentificationEntrySchema
  alias Bolognesa.Infrastructure.Persistence.IdentificationSchema
  alias Bolognesa.Infrastructure.Persistence.InspectionSchema
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.{MusicImportSchema, MusicTrackSchema}
  alias Bolognesa.Playback.Domain.ReadModels.Source
  alias Bolognesa.Playback.Domain.ReadModels.TechnicalTrack
  alias Bolognesa.Repo

  @impl true
  def find_source(catalog_entry_id, file_id) do
    query =
      from entry in CatalogEntrySchema,
        join: relation in IdentificationEntrySchema,
        on: relation.catalog_entry_id == entry.id,
        join: identification in IdentificationSchema,
        on: identification.id == relation.identification_id,
        join: file in MediaFileSchema,
        on: file.id == identification.media_file_id,
        join: library in LibrarySchema,
        on: library.id == file.library_id,
        left_join: inspection in InspectionSchema,
        on:
          inspection.media_file_id == file.id and inspection.observed_revision == file.revision and
            inspection.state == :succeeded,
        where:
          entry.id == ^catalog_entry_id and entry.kind in [:movie, :episode] and
            file.id == ^file_id and
            identification.state in [:automatic, :manual],
        select: %{
          path: library.path,
          relative_path: file.relative_path,
          size_bytes: file.size_bytes,
          modified_at: file.modified_at,
          availability: file.availability,
          revision: file.revision,
          format: inspection.format,
          duration_ms: inspection.duration_ms,
          tracks: inspection.tracks
        }

    case Repo.one(query, log: false) do
      nil ->
        {:error, :not_found}

      %{availability: :missing} ->
        {:error, :missing}

      %{availability: :available} = source ->
        {:ok,
         %Source{
           path: source.path,
           relative_path: source.relative_path,
           size_bytes: source.size_bytes,
           modified_at: source.modified_at,
           revision: source.revision,
           format: source.format,
           duration_ms: source.duration_ms,
           tracks: tracks(source.tracks)
         }}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  @impl true
  def find_track_source(track_id, file_id) do
    query =
      from(track in MusicTrackSchema,
        join: file in MediaFileSchema,
        on: file.id == track.media_file_id,
        join: library in LibrarySchema,
        on: library.id == file.library_id,
        join: inspection in InspectionSchema,
        on: inspection.media_file_id == file.id,
        join: import_state in MusicImportSchema,
        on: import_state.media_file_id == file.id,
        where: track.id == ^track_id,
        where: file.id == ^file_id,
        where:
          library.content_type == :music and
            track.library_id == library.id,
        where: inspection.state == :succeeded,
        where:
          inspection.observed_revision == file.revision and
            track.observed_revision == file.revision and
            track.inspection_token == inspection.token,
        where:
          import_state.state == :succeeded and
            import_state.inspection_token == inspection.token and
            import_state.observed_revision == file.revision,
        select: {file, library.path, inspection}
      )

    music_source(Repo.one(query, log: false))
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp music_source(nil), do: {:error, :not_found}
  defp music_source({%{availability: :missing}, _path, _inspection}), do: {:error, :missing}

  defp music_source({file, path, inspection}) do
    source_tracks = tracks(inspection.tracks)

    if Enum.any?(source_tracks, &(&1.kind == :audio)) do
      {:ok,
       %Source{
         path: path,
         relative_path: file.relative_path,
         size_bytes: file.size_bytes,
         modified_at: file.modified_at,
         revision: file.revision,
         format: inspection.format,
         duration_ms: inspection.duration_ms,
         tracks: source_tracks
       }}
    else
      {:error, :not_found}
    end
  end

  defp tracks(%{"items" => items}) when is_list(items) do
    Enum.flat_map(items, fn row ->
      case row do
        %{"kind" => kind, "codec" => codec} when kind in ["video", "audio", "subtitle"] ->
          [%TechnicalTrack{kind: track_kind(kind), codec: codec}]

        _ ->
          []
      end
    end)
  end

  defp tracks(_), do: []

  defp track_kind("video"), do: :video
  defp track_kind("audio"), do: :audio
  defp track_kind("subtitle"), do: :subtitle
end
