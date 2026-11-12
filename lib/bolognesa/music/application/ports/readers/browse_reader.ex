defmodule Bolognesa.Music.Application.Ports.Readers.BrowseReader do
  @moduledoc """
  Library-scoped artist and album browsing.

  Album `last_played_at` is the latest activity for the account across all tracks
  currently associated with the album, including temporarily missing files. It is
  nil without activity and does not indicate album completion. Artist items have
  no activity date. Aggregation is independent of browsing filters and pagination.
  """
  alias Bolognesa.Music.Domain.Entities.Artist
  alias Bolognesa.Music.Domain.ReadModels.{BrowsePage, RecentAlbum}
  @type adapter :: atom()
  @type kind :: :artists | :albums
  @callback browse(
              kind(),
              Artist.id() | nil,
              String.t(),
              pos_integer(),
              library_id :: pos_integer() | nil,
              user_id :: pos_integer()
            ) :: {:ok, BrowsePage.t()} | {:error, :not_found | :unavailable}

  @doc """
  Returns up to three distinct available albums with account activity, latest
  first, breaking album ties by ID ascending and track ties by ID ascending.
  Includes the latest heard track even if missing, plus the last available track
  in album queue order. Empty activity returns an empty list.
  """
  @callback list_recent_albums(library_id :: pos_integer() | nil, user_id :: pos_integer()) ::
              {:ok, [RecentAlbum.t()]} | {:error, :not_found | :unavailable}
end
