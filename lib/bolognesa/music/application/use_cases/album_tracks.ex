defmodule Bolognesa.Music.Application.UseCases.AlbumTracks do
  @moduledoc "Authorize album tracks and bounded album playback queues."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.Actor
  alias Bolognesa.Music.Application.Dto.{Track, TrackPage}
  alias Bolognesa.Music.Application.Ports.Readers.TracksReader
  @type error :: :forbidden | :invalid_query | :not_found | :unavailable | :album_too_large
  @type result :: {:ok, TrackPage.t()} | {:error, error()}
  @type queue_result :: {:ok, [Track.t()]} | {:error, error()}
  @spec call(
          Actor.t() | nil,
          pos_integer(),
          String.t(),
          pos_integer(),
          pos_integer() | nil,
          TracksReader.adapter()
        ) :: result()
  def call(actor, id, query, page, library, reader) do
    with :ok <- validate(actor, id, query, page, library),
         {:ok, result} <- reader.list_album_tracks(id, query, page, library, 50) do
      {:ok, TrackPage.from_domain(result)}
    end
  end

  @spec queue(Actor.t() | nil, pos_integer(), pos_integer() | nil, TracksReader.adapter()) ::
          queue_result()
  def queue(actor, id, library, reader) do
    with :ok <- validate(actor, id, "", 1, library),
         {:ok, result} <- reader.list_album_tracks(id, "", 1, library, 501),
         true <- result.total <= 500 and length(result.items) <= 500 do
      {:ok, Enum.map(result.items, &Track.from_domain/1)}
    else
      false -> {:error, :album_too_large}
      error -> error
    end
  end

  defp validate(actor, id, query, page, library) do
    with :ok <- Accounts.authorize(actor, :admin) do
      valid_query(id, query, page, library)
    end
  end

  defp valid_query(id, query, page, library) do
    if valid_id?(id) and valid_text?(query) and is_integer(page) and page in 1..100_000 and
         valid_library?(library),
       do: :ok,
       else: {:error, :invalid_query}
  end

  defp valid_id?(id), do: is_integer(id) and id > 0

  defp valid_text?(query),
    do: is_binary(query) and String.valid?(query) and byte_size(query) <= 256

  defp valid_library?(nil), do: true
  defp valid_library?(id), do: valid_id?(id)
end
