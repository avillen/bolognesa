defmodule Bolognesa.Playback do
  @moduledoc "Authorize a movie version for direct playback."

  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Playback.Application.StartPlayback
  alias Bolognesa.Playback.Infrastructure.Persistence.EctoPlaybackRepository

  @spec start(Actor.t() | nil, integer(), integer()) ::
          {:ok, map()} | {:error, :forbidden | :not_found | :missing | :unavailable}
  def start(actor, movie_id, file_id),
    do: StartPlayback.call(actor, movie_id, file_id, EctoPlaybackRepository)
end
