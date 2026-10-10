defmodule Bolognesa.Playback.Application.StartPlayback do
  @moduledoc "Authorize and select a currently linked physical movie version."

  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Playback.Application.Ports.PlaybackRepository
  alias Bolognesa.Playback.Domain.Source

  @spec call(Actor.t(), integer(), integer(), PlaybackRepository.adapter()) ::
          {:ok, Source.t()}
          | {:error, :forbidden | :not_found | :missing | :unavailable}
  def call(actor, movie_id, file_id, repository) do
    with :ok <- Identity.authorize(actor, :admin),
         true <- is_integer(movie_id) and movie_id > 0 and is_integer(file_id) and file_id > 0 do
      repository.find_source(movie_id, file_id)
    else
      false -> {:error, :not_found}
      error -> error
    end
  end
end
