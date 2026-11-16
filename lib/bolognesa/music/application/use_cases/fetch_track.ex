defmodule Bolognesa.Music.Application.UseCases.FetchTrack do
  @moduledoc "Authorize and return one currently available music track."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Music.Application.Ports.Readers.TracksReader
  alias Bolognesa.Music.Domain.ReadModels.TrackRow

  @type result :: {:ok, TrackRow.t()} | {:error, :forbidden | :not_found | :unavailable}
  @spec call(AuthenticatedUser.t() | nil, integer(), TracksReader.adapter()) :: result()
  def call(actor, track_id, reader) do
    with :ok <- Accounts.authorize(actor, :admin),
         true <- is_integer(track_id) and track_id > 0 do
      reader.fetch_track(track_id)
    else
      false -> {:error, :not_found}
      error -> error
    end
  end
end
