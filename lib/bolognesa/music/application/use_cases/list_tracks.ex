defmodule Bolognesa.Music.Application.UseCases.ListTracks do
  @moduledoc "Authorize and validate local musical reads."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.Actor
  alias Bolognesa.Music.Application.Dto.TrackPage
  alias Bolognesa.Music.Application.Ports.Readers.TracksReader
  @type error :: :forbidden | :invalid_query | :not_found | :unavailable
  @type result :: {:ok, TrackPage.t()} | {:error, error()}
  @spec call(
          Actor.t() | nil,
          String.t(),
          pos_integer(),
          pos_integer() | nil,
          TracksReader.adapter()
        ) :: result()
  def call(actor, query, page, library_id, reader) do
    with :ok <- Accounts.authorize(actor, :admin),
         true <- valid?(query, page, library_id),
         {:ok, result} <- reader.list_tracks(query, page, library_id) do
      {:ok, TrackPage.from_domain(result)}
    else
      false -> {:error, :invalid_query}
      error -> error
    end
  end

  defp valid?(query, page, library_id) do
    is_binary(query) and byte_size(query) <= 256 and String.valid?(query) and
      is_integer(page) and page in 1..100_000 and
      (is_nil(library_id) or (is_integer(library_id) and library_id > 0))
  end
end
