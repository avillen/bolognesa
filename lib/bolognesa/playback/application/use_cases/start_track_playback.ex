defmodule Bolognesa.Playback.Application.UseCases.StartTrackPlayback do
  @moduledoc "Authorize and select a currently linked physical movie version."

  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Entities.Actor
  alias Bolognesa.Playback.Application.Ports.Repositories.PlaybackRepository
  alias Bolognesa.Playback.Domain.ReadModels.Source

  @spec call(Actor.t(), integer(), integer(), PlaybackRepository.adapter()) ::
          {:ok, Source.t()}
          | {:error, :forbidden | :not_found | :missing | :unavailable}
  def call(actor, track_id, file_id, repository) do
    with :ok <- Identity.authorize(actor, :admin),
         true <-
           is_integer(track_id) and track_id > 0 and is_integer(file_id) and
             file_id > 0 do
      repository.find_track_source(track_id, file_id)
    else
      false -> {:error, :not_found}
      error -> error
    end
  end
end
