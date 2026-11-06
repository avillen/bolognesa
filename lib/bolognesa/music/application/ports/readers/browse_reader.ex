defmodule Bolognesa.Music.Application.Ports.Readers.BrowseReader do
  @moduledoc """
  Library-scoped artist and album browsing.

  Album `last_played_at` is the latest activity for the account across all tracks
  currently associated with the album, including temporarily missing files. It is
  nil without activity and does not indicate album completion. Artist items have
  no activity date. Aggregation is independent of browsing filters and pagination.
  """
  alias Bolognesa.Music.Domain.ReadModels.BrowsePage
  @type adapter :: atom()
  @type kind :: :artists | :albums
  @callback browse(
              kind(),
              artist_id :: pos_integer() | nil,
              String.t(),
              pos_integer(),
              library_id :: pos_integer() | nil,
              user_id :: pos_integer()
            ) :: {:ok, BrowsePage.t()} | {:error, :not_found | :unavailable}
end
