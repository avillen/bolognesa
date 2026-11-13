defmodule Bolognesa.Music.Infrastructure.Readers.EctoBrowseReader do
  @moduledoc false
  @behaviour Bolognesa.Music.Application.Ports.Readers.BrowseReader
  import Ecto.Query

  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.MusicAlbumSchema
  alias Bolognesa.Infrastructure.Persistence.MusicArtistSchema
  alias Bolognesa.Infrastructure.Persistence.MusicTrackSchema

  alias Bolognesa.Music.Domain.ReadModels.BrowseItem
  alias Bolognesa.Music.Domain.ReadModels.BrowsePage
  alias Bolognesa.Music.Domain.ReadModels.RecentAlbum
  alias Bolognesa.Repo

  @impl true
  def list_recent_albums(library_id, user_id) do
    with :ok <- library_scope(library_id) do
      latest =
        from(track in MusicTrackSchema,
          join: activity in "music_listening_activity",
          on: activity.track_id == track.id and activity.user_id == ^user_id,
          join: file in MediaFileSchema,
          on: file.id == track.media_file_id,
          where: track.album_id == parent_as(:album).id,
          order_by: [desc: activity.last_played_at, asc: track.id],
          limit: 1,
          select: %{
            track_id: track.id,
            file_id: file.id,
            track_title: track.title,
            track_available?: file.availability == :available,
            last_played_at: type(activity.last_played_at, :utc_datetime_usec)
          }
        )

      final =
        from(track in MusicTrackSchema,
          join: file in MediaFileSchema,
          on: file.id == track.media_file_id,
          where: track.album_id == parent_as(:album).id and file.availability == :available,
          order_by: [
            desc_nulls_first: track.disc_number,
            desc_nulls_first: track.track_number,
            desc: file.relative_path,
            desc: track.id
          ],
          limit: 1,
          select: %{id: track.id}
        )

      albums =
        collection(:albums, nil) |> scope(library_id) |> exclude(:order_by) |> exclude(:select)

      query =
        from([album, artist] in albums,
          inner_lateral_join: latest in subquery(latest),
          on: true,
          inner_lateral_join: final in subquery(final),
          on: true,
          order_by: [desc: latest.last_played_at, asc: album.id],
          limit: 3,
          select: %{
            id: album.id,
            title: album.title,
            artist: artist.name,
            last_played_at: latest.last_played_at,
            track_id: latest.track_id,
            file_id: latest.file_id,
            track_title: latest.track_title,
            track_available?: latest.track_available?,
            final_track_id: final.id
          }
        )

      {:ok, query |> Repo.all(log: false) |> Enum.map(&struct!(RecentAlbum, &1))}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  @impl true
  def browse(kind, artist_id, text, page, library_id, user_id) do
    with :ok <- library_scope(library_id),
         {:ok, heading} <- artist_heading(artist_id, library_id) do
      query = collection(kind, artist_id) |> scope(library_id) |> search(text, kind)
      total = Repo.aggregate(query, :count, :id, log: false)

      items =
        query
        |> order_by([row], asc: row.id)
        |> limit(50)
        |> offset(^((page - 1) * 50))
        |> with_activity(kind, user_id)
        |> Repo.all(log: false)
        |> Enum.map(&struct!(BrowseItem, &1))

      {:ok, %BrowsePage{items: items, total: total, page: page, heading: heading}}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp with_activity(query, :artists, _user_id), do: query

  defp with_activity(query, :albums, user_id) do
    latest =
      from(track in MusicTrackSchema,
        join: activity in "music_listening_activity",
        on: activity.track_id == track.id and activity.user_id == ^user_id,
        where: track.album_id == parent_as(:album).id,
        select: max(activity.last_played_at)
      )

    select_merge(query, [], %{
      last_played_at: type(fragment("?", subquery(latest)), :utc_datetime_usec)
    })
  end

  defp library_scope(nil), do: :ok

  defp library_scope(id) do
    case Repo.get(LibrarySchema, id, log: false) do
      %{content_type: :music} -> :ok
      _ -> {:error, :not_found}
    end
  end

  defp artist_heading(nil, _library), do: {:ok, nil}

  defp artist_heading(id, library) do
    case Repo.one(scope(from(a in MusicArtistSchema, where: a.id == ^id), library), log: false) do
      nil -> {:error, :not_found}
      artist -> {:ok, artist.name}
    end
  end

  defp collection(:artists, _artist) do
    from(a in MusicArtistSchema,
      as: :artist,
      where:
        exists(
          from(t in MusicTrackSchema,
            join: f in MediaFileSchema,
            on: f.id == t.media_file_id,
            left_join: album in MusicAlbumSchema,
            on: album.id == t.album_id,
            where:
              f.availability == :available and
                is_nil(album.artist_id) and t.artist_id == parent_as(:artist).id,
            select: 1
          )
        ) or
          exists(
            from(album in MusicAlbumSchema,
              join: t in MusicTrackSchema,
              on: t.album_id == album.id,
              join: f in MediaFileSchema,
              on: f.id == t.media_file_id,
              where:
                f.availability == :available and
                  album.artist_id == parent_as(:artist).id,
              select: 1
            )
          ),
      order_by: [asc: a.normalized_name],
      select: %{id: a.id, title: a.name, subtitle: nil, year: nil}
    )
  end

  defp collection(:albums, artist_id) do
    query =
      from(a in MusicAlbumSchema,
        as: :album,
        left_join: artist in MusicArtistSchema,
        on: artist.id == a.artist_id,
        where:
          exists(
            from(t in MusicTrackSchema,
              join: f in MediaFileSchema,
              on: f.id == t.media_file_id,
              where: t.album_id == parent_as(:album).id and f.availability == :available,
              select: 1
            )
          ),
        order_by: [asc: a.normalized_title],
        select: %{id: a.id, title: a.title, subtitle: artist.name, year: a.year}
      )

    filter_artist(query, artist_id)
  end

  defp filter_artist(query, nil), do: query

  defp filter_artist(query, id) do
    where(
      query,
      [a],
      a.artist_id == ^id or
        exists(
          from(t in MusicTrackSchema,
            join: f in MediaFileSchema,
            on: f.id == t.media_file_id,
            where:
              t.album_id == parent_as(:album).id and t.artist_id == ^id and
                f.availability == :available,
            select: 1
          )
        )
    )
  end

  defp scope(query, nil), do: query
  defp scope(query, library), do: where(query, [row], row.library_id == ^library)
  defp search(query, "", _kind), do: query

  defp search(query, text, kind) do
    pattern =
      "%" <>
        (text
         |> String.replace("\\", "\\\\")
         |> String.replace("%", "\\%")
         |> String.replace("_", "\\_")) <> "%"

    search_pattern(query, kind, pattern)
  end

  defp search_pattern(query, :artists, pattern),
    do: where(query, [row], ilike(row.name, ^pattern))

  defp search_pattern(query, :albums, pattern),
    do: where(query, [row, artist], ilike(row.title, ^pattern) or ilike(artist.name, ^pattern))
end
