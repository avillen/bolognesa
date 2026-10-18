defmodule Bolognesa.Playback.Application.UseCases.StartVideoPlayback do
  @moduledoc "Authorize and select a currently linked movie or episode video file."

  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Playback.Application.Ports.Repositories.PlaybackRepository
  alias Bolognesa.Playback.Domain.ReadModels.Source
  alias Bolognesa.Playback.Domain.ValueObjects.ContentRef

  @spec call(AuthenticatedUser.t(), ContentRef.t(), integer(), PlaybackRepository.adapter()) ::
          {:ok, Source.t()}
          | {:error, :forbidden | :not_found | :missing | :unavailable}
  def call(actor, content_ref, file_id, repository) do
    with :ok <- Accounts.authorize(actor, :admin),
         true <-
           ContentRef.valid?(content_ref) and is_integer(file_id) and
             file_id > 0 do
      repository.find_video_source(content_ref, file_id)
    else
      false -> {:error, :not_found}
      error -> error
    end
  end
end
