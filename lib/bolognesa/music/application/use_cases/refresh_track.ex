defmodule Bolognesa.Music.Application.UseCases.RefreshTrack do
  @moduledoc "Refresh a stable local track from current observations."
  alias Bolognesa.Music.Application.Ports.Readers.ObservationsReader
  alias Bolognesa.Music.Application.Ports.Repositories.MusicRepository
  alias Bolognesa.Music.Domain.ValueObjects.TrackMetadata
  @type result :: :ok | {:error, :unavailable}
  @spec call(
          pos_integer(),
          pos_integer(),
          ObservationsReader.adapter(),
          MusicRepository.adapter()
        ) :: result()
  def call(file_id, revision, reader, repository) do
    case reader.current(file_id, revision) do
      {:ok, :stale} -> :ok
      {:ok, observation} -> apply_current(observation, repository)
      {:error, :unavailable} = error -> error
    end
  end

  defp apply_current(observation, repository) do
    case repository.apply_observation(observation, TrackMetadata.from_observation(observation)) do
      {:ok, _result} -> :ok
      {:error, :unavailable} = error -> error
    end
  end
end
