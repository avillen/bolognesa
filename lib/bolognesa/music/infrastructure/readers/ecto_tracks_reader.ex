defmodule Bolognesa.Music.Infrastructure.Readers.EctoTracksReader do
  @moduledoc false
  @behaviour Bolognesa.Music.Application.Ports.Readers.TracksReader
  import Ecto.Query
  alias Bolognesa.Infrastructure.Persistence.{InspectionSchema, LibrarySchema, MediaFileSchema}

  alias Bolognesa.Infrastructure.Persistence.{
    MusicAlbumSchema,
    MusicArtistSchema,
    MusicImportSchema,
    MusicTrackSchema
  }

  alias Bolognesa.Libraries.Domain.ValueObjects.Inspection.MusicTags
  alias Bolognesa.Music.Domain.ReadModels.{TrackPage, TrackRow}
  alias Bolognesa.Music.Domain.ValueObjects.{Observation, TrackMetadata}
  alias Bolognesa.Repo
  @impl true
  def list_tracks(query, page, library_id) do
    with :ok <- library_scope(library_id) do
      base = base_query(library_id) |> search(query)
      total = Repo.aggregate(base, :count, :id, log: false)

      rows =
        Repo.all(
          from([file, _library, inspection, track, artist, album, import_state] in base,
            order_by: [
              asc:
                fragment(
                  "COALESCE(?, regexp_replace(regexp_replace(encode(?, 'escape'), '^.*/', ''), '(.+)\\.[^.]*$', '\\1'))",
                  track.title,
                  file.relative_path
                ),
              asc: file.id
            ],
            limit: 50,
            offset: ^((page - 1) * 50),
            select: {file, inspection, track, artist.name, album.title, import_state}
          ),
          log: false
        )

      {:ok, %TrackPage{items: Enum.map(rows, &row/1), total: total, page: page}}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp library_scope(nil), do: :ok

  defp library_scope(id) do
    case Repo.get(LibrarySchema, id) do
      %{content_type: :music} -> :ok
      _ -> {:error, :not_found}
    end
  end

  defp base_query(library_id) do
    query =
      from(file in MediaFileSchema,
        join: library in LibrarySchema,
        on: library.id == file.library_id,
        left_join: inspection in InspectionSchema,
        on: inspection.media_file_id == file.id,
        left_join: track in MusicTrackSchema,
        on: track.media_file_id == file.id,
        left_join: artist in MusicArtistSchema,
        on: artist.id == track.artist_id,
        left_join: album in MusicAlbumSchema,
        on: album.id == track.album_id,
        left_join: import_state in MusicImportSchema,
        on: import_state.media_file_id == file.id,
        where: library.content_type == :music and file.availability == :available
      )

    if library_id, do: where(query, [file], file.library_id == ^library_id), else: query
  end

  defp search(query, ""), do: query

  defp search(query, text) do
    pattern =
      "%" <>
        (text
         |> String.replace("\\", "\\\\")
         |> String.replace("%", "\\%")
         |> String.replace("_", "\\_")) <> "%"

    where(
      query,
      [file, _library, _inspection, track, artist, album],
      ilike(track.title, ^pattern) or ilike(artist.name, ^pattern) or ilike(album.title, ^pattern) or
        ilike(fragment("encode(?, 'escape')", file.relative_path), ^pattern)
    )
  end

  defp row({file, inspection, track, artist, album, import_state}) do
    state = state(file, inspection, track, import_state)

    title =
      if track,
        do: track.title,
        else:
          TrackMetadata.from_observation(%Observation{
            relative_path: file.relative_path,
            music_tags: %MusicTags{}
          }).title

    %TrackRow{
      id: track && track.id,
      file_id: file.id,
      title: title,
      artist: artist,
      album: album,
      duration_ms: inspection && inspection.duration_ms,
      state: state,
      failure_reason: failure(state, inspection, import_state)
    }
  end

  defp state(_file, nil, _track, _import), do: :pending

  defp state(file, inspection, track, import_state) do
    cond do
      inspection.observed_revision != file.revision -> :pending
      inspection.state == :failed -> :inspection_failed
      inspection.state != :succeeded -> :pending
      true -> imported_state(file, inspection, track, import_state)
    end
  end

  defp imported_state(_file, _inspection, _track, nil), do: :pending

  defp imported_state(file, inspection, track, import_state) do
    cond do
      import_state.inspection_token != inspection.token -> :pending
      import_state.state == :failed -> :import_failed
      import_state.state == :succeeded -> ready_state(file, inspection, track)
      true -> :pending
    end
  end

  defp ready_state(_file, _inspection, nil), do: :pending

  defp ready_state(file, inspection, track) do
    if track.observed_revision == file.revision and track.inspection_token == inspection.token,
      do: :ready,
      else: :pending
  end

  defp failure(:inspection_failed, inspection, _import), do: inspection.failure_reason
  defp failure(:import_failed, _inspection, import_state), do: import_state.failure_reason
  defp failure(_state, _inspection, _import), do: nil
end
