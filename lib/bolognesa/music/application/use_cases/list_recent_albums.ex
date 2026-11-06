defmodule Bolognesa.Music.Application.UseCases.ListRecentAlbums do
  @moduledoc "Authorized, bounded lookup of the account's recently heard albums."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Music.Application.Dto.RecentAlbum
  alias Bolognesa.Music.Application.Ports.Readers.BrowseReader

  @type result ::
          {:ok, [RecentAlbum.t()]}
          | {:error, :forbidden | :invalid_query | :not_found | :unavailable}

  @spec call(AuthenticatedUser.t() | nil, pos_integer() | nil, BrowseReader.adapter()) :: result()
  def call(actor, library_id, reader) do
    with :ok <- Accounts.authorize(actor, :admin),
         true <- is_nil(library_id) or (is_integer(library_id) and library_id > 0),
         {:ok, albums} <- reader.list_recent_albums(library_id, actor.id) do
      {:ok, Enum.map(albums, &RecentAlbum.from_domain/1)}
    else
      false -> {:error, :invalid_query}
      other -> other
    end
  end
end
