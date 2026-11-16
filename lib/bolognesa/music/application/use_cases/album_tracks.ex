defmodule Bolognesa.Music.Application.UseCases.AlbumTracks do
  @moduledoc "Authorize album tracks and bounded album playback queues."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Music.Application.Dto.Track
  alias Bolognesa.Music.Application.Dto.TrackPage
  alias Bolognesa.Music.Application.Ports.Readers.TracksReader
  alias Bolognesa.Music.Application.ReadQuery
  alias Bolognesa.Music.Domain.Entities.Album
  @type error :: :forbidden | :invalid_query | :not_found | :unavailable | :album_too_large
  @type result :: {:ok, TrackPage.t()} | {:error, error()}
  @type queue_result :: {:ok, [Track.t()]} | {:error, error()}
  @spec call(
          AuthenticatedUser.t() | nil,
          Album.id(),
          String.t(),
          pos_integer(),
          pos_integer() | nil,
          TracksReader.adapter()
        ) :: result()
  def call(actor, id, query, page, library, reader) do
    with :ok <- validate(actor, id, query, page, library),
         {:ok, result} <- reader.list_album_tracks(id, query, page, library, 50, actor.id) do
      {:ok, TrackPage.from_domain(result)}
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
      {:ok, Enum.map(result.items, &Track.from_domain/1)}
    else
      false -> {:error, :album_too_large}
      error -> error
    end
  end

  defp validate(actor, id, query, page, library) do
    with :ok <- Accounts.authorize(actor, :admin),
         true <- ReadQuery.valid_id?(id) and ReadQuery.valid?(query, page, library) do
      :ok
    else
      false -> {:error, :invalid_query}
      error -> error
    end
  end
end
