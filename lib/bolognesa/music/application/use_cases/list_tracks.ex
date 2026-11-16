defmodule Bolognesa.Music.Application.UseCases.ListTracks do
  @moduledoc "Authorize and validate local musical reads."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Music.Application.Ports.Readers.TracksReader
  alias Bolognesa.Music.Application.ReadQuery
  alias Bolognesa.Music.Domain.ReadModels.TrackPage

  @type error :: :forbidden | :invalid_query | :not_found | :unavailable
  @type result :: {:ok, TrackPage.t()} | {:error, error()}
  @spec call(
          AuthenticatedUser.t() | nil,
          String.t(),
          pos_integer(),
          pos_integer() | nil,
          TracksReader.adapter()
        ) :: result()
  def call(actor, query, page, library_id, reader) do
    with :ok <- Accounts.authorize(actor, :admin),
         true <- ReadQuery.valid?(query, page, library_id) do
      reader.list_tracks(query, page, library_id, actor.id)
    else
      false -> {:error, :invalid_query}
      error -> error
    end
  end
end
