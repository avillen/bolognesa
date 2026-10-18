defmodule Bolognesa.Playback.Infrastructure.Repositories.EctoPlaybackRepository do
  @moduledoc false
  @behaviour Bolognesa.Playback.Application.Ports.Repositories.PlaybackRepository

  import Ecto.Query

  alias Bolognesa.Infrastructure.Persistence.InspectionSchema
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.MovieIdentificationSchema
  alias Bolognesa.Infrastructure.Persistence.MusicImportSchema
  alias Bolognesa.Infrastructure.Persistence.MusicTrackSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationEpisodeSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationSchema
  alias Bolognesa.Playback.Domain.ReadModels.Source
  alias Bolognesa.Playback.Domain.ReadModels.TechnicalTrack
  alias Bolognesa.Repo

  @impl true
  def find_video_source({:movie, id}, file_id) when is_integer(id) and id > 0 do
    base =
      from identification in MovieIdentificationSchema,
        where: identification.movie_id == ^id,
        select: identification

    video_source(base, :movie, file_id)
  end

  def find_video_source({:episode, id}, file_id) when is_integer(id) and id > 0 do
    base =
      from identification in SeriesIdentificationSchema,
        join: relation in SeriesIdentificationEpisodeSchema,
        on: relation.identification_id == identification.id,
        where: relation.episode_id == ^id,
        select: identification

    video_source(base, :series, file_id)
  end

  def find_video_source(_, _), do: {:error, :not_found}

  defp video_source(base, content_type, file_id) do
    query =
      from identification in subquery(base),
        join: file in MediaFileSchema,
        on: file.id == identification.media_file_id,
        join: library in LibrarySchema,
        on: library.id == file.library_id,
        left_join: inspection in InspectionSchema,
        on:
          inspection.media_file_id == file.id and inspection.observed_revision == file.revision and
            inspection.state == :succeeded,
        where: file.id == ^file_id and library.content_type == ^content_type,
        where: identification.state in [:automatic, :manual],
        select: {file, library.path, inspection}

    video_result(Repo.one(query, log: false))
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp video_result(nil), do: {:error, :not_found}
  defp video_result({%{availability: :missing}, _, _}), do: {:error, :missing}

  defp video_result({file, path, inspection}) do
    {:ok,
     %Source{
       path: path,
       relative_path: file.relative_path,
       size_bytes: file.size_bytes,
       modified_at: file.modified_at,
       revision: file.revision,
       format: if(inspection, do: inspection.format),
       duration_ms: if(inspection, do: inspection.duration_ms),
       tracks: if(inspection, do: tracks(inspection.tracks), else: [])
     }}
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
