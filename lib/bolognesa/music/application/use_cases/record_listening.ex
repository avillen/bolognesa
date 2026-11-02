defmodule Bolognesa.Music.Application.UseCases.RecordListening do
  @moduledoc "Record a qualifying playback for the authenticated listener."
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Music.Application.Ports.Readers.TracksReader
  alias Bolognesa.Music.Application.Ports.Repositories.ListeningActivityRepository
  alias Bolognesa.Music.Application.UseCases.FetchTrack

  @type result :: :ok | {:error, :forbidden | :not_found | :unavailable}
  @spec call(
          AuthenticatedUser.t() | nil,
          integer(),
          integer(),
          TracksReader.adapter(),
          ListeningActivityRepository.adapter()
        ) :: result()
  def call(actor, track_id, file_id, reader, repository) do
    with {:ok, track} <- FetchTrack.call(actor, track_id, reader),
         true <- track.file_id == file_id and track.state == :ready do
      repository.record(actor.id, track_id)
    else
      false -> {:error, :not_found}
      error -> error
    end
  end
end
