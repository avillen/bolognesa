defmodule Bolognesa.Music.Infrastructure.Readers.EctoBrowseReader do
  @moduledoc false
  @behaviour Bolognesa.Music.Application.Ports.Readers.BrowseReader
  import Ecto.Query

  alias Bolognesa.Infrastructure.Persistence.{
    LibrarySchema,
    MediaFileSchema,
    MusicAlbumSchema,
    MusicArtistSchema,
    MusicTrackSchema
  }

  alias Bolognesa.Music.Domain.ReadModels.{BrowseItem, BrowsePage}
  alias Bolognesa.Repo

  @impl true
  def browse(kind, artist_id, text, page, library_id) do
    with :ok <- library_scope(library_id),
         {:ok, heading} <- artist_heading(artist_id, library_id) do
      query = collection(kind, artist_id) |> scope(library_id) |> search(text, kind)
      total = Repo.aggregate(query, :count, :id, log: false)

      items =
        query
        |> order_by([row], asc: row.id)
        |> limit(50)
        |> offset(^((page - 1) * 50))
        |> Repo.all(log: false)
        |> Enum.map(&struct!(BrowseItem, &1))

      {:ok, %BrowsePage{items: items, total: total, page: page, heading: heading}}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
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
                (t.artist_id == parent_as(:artist).id or album.artist_id == parent_as(:artist).id),
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
