defmodule Bolognesa.Music.Infrastructure.Repositories.EctoMusicRepository do
  @moduledoc false
  @behaviour Bolognesa.Music.Application.Ports.Repositories.MusicRepository
  import Ecto.Query
  alias Bolognesa.Infrastructure.Persistence.{InspectionSchema, LibrarySchema, MediaFileSchema}

  alias Bolognesa.Infrastructure.Persistence.{
    MusicAlbumSchema,
    MusicArtistSchema,
    MusicImportSchema,
    MusicTrackSchema
  }

  alias Bolognesa.Music.Domain.Policies.Grouping
  alias Bolognesa.Music.Infrastructure.Repositories.EctoMusicRepository.MusicMapper
  alias Bolognesa.Repo

  @impl true
  def apply_observation(observation, metadata) do
    case Repo.transaction(fn -> apply_locked(observation, metadata) end) do
      {:ok, result} -> result
      {:error, _reason} -> {:error, :unavailable}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
    Ecto.ConstraintError -> {:error, :unavailable}
  end

  defp apply_locked(observation, metadata) do
    file =
      Repo.one(
        from(row in MediaFileSchema, where: row.id == ^observation.file_id, lock: "FOR UPDATE"),
        log: false
      )

    inspection =
      Repo.one(
        from(row in InspectionSchema,
          where: row.media_file_id == ^observation.file_id,
          lock: "FOR UPDATE"
        ),
        log: false
      )

    import_state =
      Repo.one(
        from(row in MusicImportSchema,
          where: row.media_file_id == ^observation.file_id,
          lock: "FOR UPDATE"
        ),
        log: false
      )

    if current?(file, inspection, observation) do
      persist(observation, metadata, import_state)
    else
      {:ok, :stale}
    end
  end

  defp current?(nil, _inspection, _observation), do: false
  defp current?(_file, nil, _observation), do: false

  defp current?(file, inspection, observation) do
    library = Repo.get!(LibrarySchema, file.library_id)

    library.content_type == :music and file.availability == :available and
      file.revision == observation.revision and file.library_id == observation.library_id and
      inspection.observed_revision == observation.revision and inspection.state == :succeeded and
      inspection.token == observation.inspection_token and
      Enum.any?(inspection.tracks["items"] || [], &(&1["kind"] == "audio"))
  end

  defp persist(observation, metadata, import_state) do
    artist_id = artist(observation.library_id, metadata.artist)
    album_artist_id = artist(observation.library_id, metadata.album_artist)
    album_id = album(observation.library_id, metadata, album_artist_id)

    attrs = %{
      media_file_id: observation.file_id,
      library_id: observation.library_id,
      title: metadata.title,
      artist_id: artist_id,
      album_id: album_id,
      disc_number: metadata.disc_number,
      track_number: metadata.track_number,
      year: metadata.year,
      observed_revision: observation.revision,
      inspection_token: observation.inspection_token
    }

    Repo.insert!(MusicTrackSchema.changeset(%MusicTrackSchema{}, attrs),
      on_conflict: {:replace, Map.keys(Map.delete(attrs, :media_file_id)) ++ [:updated_at]},
      conflict_target: [:media_file_id],
      log: false
    )

    Repo.insert!(
      MusicImportSchema.changeset(%MusicImportSchema{}, %{
        media_file_id: observation.file_id,
        observed_revision: observation.revision,
        inspection_token: observation.inspection_token,
        state: :succeeded,
        job_id: import_state && import_state.job_id,
        failure_reason: nil,
        finished_at: DateTime.utc_now()
      }),
      on_conflict:
        {:replace,
         [
           :observed_revision,
           :inspection_token,
           :state,
           :failure_reason,
           :finished_at,
           :updated_at
         ]},
      conflict_target: [:media_file_id],
      log: false
    )

    {:ok,
     Repo.get_by!(MusicTrackSchema, [media_file_id: observation.file_id], log: false)
     |> MusicMapper.to_track()}
  end

  defp artist(_library_id, nil), do: nil

  defp artist(library_id, name) do
    key = Grouping.artist_key(name)

    Repo.insert!(
      MusicArtistSchema.changeset(%MusicArtistSchema{}, %{
        library_id: library_id,
        name: name,
        normalized_name: key
      }),
      on_conflict: :nothing,
      conflict_target: [:library_id, :normalized_name],
      log: false
    )

    Repo.get_by!(MusicArtistSchema, [library_id: library_id, normalized_name: key], log: false).id
  end

  defp album(_library_id, %{album: nil}, _artist_id), do: nil

  defp album(library_id, metadata, artist_id) do
    {_, parent, title_key, artist_key} =
      Grouping.album_key(
        library_id,
        metadata.source_parent,
        metadata.album,
        metadata.album_artist
      )

    attrs = %{
      library_id: library_id,
      source_parent: parent,
      title: metadata.album,
      normalized_title: title_key,
      artist_id: artist_id,
      album_artist_key: artist_key,
      year: metadata.year
    }

    keys = [:library_id, :source_parent, :normalized_title, :album_artist_key]

    Repo.insert!(MusicAlbumSchema.changeset(%MusicAlbumSchema{}, attrs),
      on_conflict: :nothing,
      conflict_target: keys,
      log: false
    )

    Repo.get_by!(MusicAlbumSchema, Map.take(attrs, keys), log: false).id
  end
end
