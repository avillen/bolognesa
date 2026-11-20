defmodule Bolognesa.Music.Application.UseCases.AlbumTracks do
  @moduledoc "Authorize album tracks and bounded album playback queues."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Music.Application.Ports.Readers.TracksReader
  alias Bolognesa.Music.Domain.Entities.Album
  alias Bolognesa.Music.Domain.ReadModels.TrackPage
  alias Bolognesa.Music.Domain.ReadModels.TrackRow
  alias Bolognesa.ReadQuery

  @type error ::
          :forbidden
          | :invalid_query
          | :invalid_page
          | :not_found
          | :unavailable
          | :album_too_large
  @type result :: {:ok, TrackPage.t()} | {:error, error()}
  @type queue_result :: {:ok, [TrackRow.t()]} | {:error, error()}
  @spec call(
          AuthenticatedUser.t() | nil,
          Album.id(),
          String.t(),
          pos_integer(),
          pos_integer() | nil,
          TracksReader.adapter()
        ) :: result()
  def call(actor, id, query, page, library, reader) do
    with :ok <- validate(actor, id, query, page, library) do
      reader.list_album_tracks(id, query, page, library, 50, actor.id)
    end
  end

  @spec queue(
          AuthenticatedUser.t() | nil,
          Album.id(),
          pos_integer() | nil,
          TracksReader.adapter()
        ) ::
          queue_result()
  def queue(actor, id, library, reader) do
    with :ok <- validate(actor, id, "", 1, library),
         {:ok, result} <- reader.list_album_tracks(id, "", 1, library, 501, actor.id),
         true <- result.total <= 500 and length(result.items) <= 500 do
      {:ok, result.items}
    else
      false -> {:error, :album_too_large}
      error -> error
    end
  end

  defp validate(actor, id, query, page, library) do
    with :ok <- Accounts.authorize(actor, :admin),
         :ok <- ReadQuery.validate_id(id) do
      ReadQuery.validate(query, page, library)
    end
  end
end
