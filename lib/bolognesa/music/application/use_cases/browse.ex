defmodule Bolognesa.Music.Application.UseCases.Browse do
  @moduledoc "Authorized, bounded browsing of existing local identities."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Music.Application.Ports.Readers.BrowseReader
  alias Bolognesa.Music.Domain.Entities.Artist
  alias Bolognesa.Music.Domain.ReadModels.BrowsePage
  alias Bolognesa.ReadQuery

  @type result ::
          {:ok, BrowsePage.t()}
          | {:error, :forbidden | :invalid_query | :not_found | :unavailable}
  @spec call(
          AuthenticatedUser.t() | nil,
          BrowseReader.kind(),
          Artist.id() | nil,
          String.t(),
          pos_integer(),
          pos_integer() | nil,
          BrowseReader.adapter()
        ) :: result()
  def call(actor, kind, artist_id, query, page, library_id, reader) do
    with :ok <- Accounts.authorize(actor, :admin),
         true <-
           kind in [:artists, :albums] and ReadQuery.valid_optional_id?(artist_id) and
             ReadQuery.valid?(query, page, library_id) do
      reader.browse(kind, artist_id, query, page, library_id, actor.id)
    else
      false -> {:error, :invalid_query}
      error -> error
    end
  end
end
