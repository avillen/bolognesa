defmodule Bolognesa.Music.Application.UseCases.ListRecentAlbums do
  @moduledoc "Authorized, bounded lookup of the account's recently heard albums."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Music.Application.Dto.RecentAlbum
  alias Bolognesa.Music.Application.Ports.Readers.BrowseReader
  alias Bolognesa.ReadQuery

  @type result ::
          {:ok, [RecentAlbum.t()]}
          | {:error, :forbidden | :invalid_query | :not_found | :unavailable}

  @spec call(AuthenticatedUser.t() | nil, pos_integer() | nil, BrowseReader.adapter()) :: result()
  def call(actor, library_id, reader) do
    with :ok <- Accounts.authorize(actor, :admin),
         :ok <- ReadQuery.validate_optional_id(library_id),
         {:ok, albums} <- reader.list_recent_albums(library_id, actor.id) do
      {:ok, Enum.map(albums, &RecentAlbum.from_domain/1)}
    end
  end
end
