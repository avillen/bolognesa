defmodule Bolognesa.Playback do
  @moduledoc "Authorize a movie version for direct playback."

  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Playback.Application.StartPlayback
  alias Bolognesa.Playback.Domain.Source
  alias Bolognesa.Playback.Infrastructure.LocalMediaFile
  alias Bolognesa.Playback.Infrastructure.Persistence.EctoPlaybackRepository

  @spec start(Actor.t(), integer(), integer()) ::
          {:ok, Source.t()} | {:error, :forbidden | :not_found | :missing | :unavailable}
  def start(actor, movie_id, file_id),
    do: StartPlayback.call(actor, movie_id, file_id, EctoPlaybackRepository)

  @spec prepare(Actor.t(), integer(), integer()) ::
          :ok
          | {:error, :forbidden | :not_found | :missing | :unavailable | LocalMediaFile.failure()}
  def prepare(actor, movie_id, file_id) do
    with {:ok, source} <- start(actor, movie_id, file_id),
         {:ok, %{device: device}} <- LocalMediaFile.open(source) do
      case :file.close(device) do
        :ok -> :ok
        {:error, _} -> {:error, :unreadable}
      end
    end
  end
end
