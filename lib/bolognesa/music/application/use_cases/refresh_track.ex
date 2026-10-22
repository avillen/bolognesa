defmodule Bolognesa.Music.Application.UseCases.RefreshTrack do
  @moduledoc "Refresh a stable local track from current observations."
  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Music.Application.Ports.Readers.ObservationsReader
  alias Bolognesa.Music.Application.Ports.Repositories.MusicRepository
  alias Bolognesa.Music.Domain.ValueObjects.TrackMetadata

  @type correlation :: %{optional(:job_id) => pos_integer(), optional(:attempt) => pos_integer()}
  @type result :: :ok | {:error, :unavailable}
  @spec call(
          pos_integer(),
          pos_integer(),
          ObservationsReader.adapter(),
          MusicRepository.adapter(),
          String.t() | nil,
          correlation()
        ) :: result()
  def call(file_id, revision, reader, repository, token \\ nil, correlation \\ %{}) do
    started = Events.started_at()

    metadata =
      Map.merge(Map.take(correlation, [:job_id, :attempt]), %{
        file_id: file_id,
        revision: revision
      })

    result = reader.current(file_id, revision)
    refresh(result, repository, token, metadata, started)
  end

  defp refresh({:ok, :stale}, _repository, _token, metadata, started),
    do: stale(metadata, started)

  defp refresh({:ok, observation}, repository, token, metadata, started)
       when is_nil(token) or observation.inspection_token == token do
    metadata = Map.put(metadata, :library_id, observation.library_id)

    result =
      repository.apply_observation(observation, TrackMetadata.from_observation(observation))

    observe_result(result, metadata, started)
  end

  defp refresh({:ok, _obsolete}, _repository, _token, metadata, started),
    do: stale(metadata, started)

  defp refresh({:error, :unavailable} = error, _repository, _token, metadata, started),
    do: observe_result(error, metadata, started)

  defp observe_result({:ok, :stale}, metadata, started), do: stale(metadata, started)

  defp observe_result({:ok, _track}, metadata, started) do
    Events.emit(:music, :import, :completed, Map.put(metadata, :result, :imported), %{
      duration_ms: Events.elapsed(started)
    })

    :ok
  end

  defp observe_result({:error, :unavailable} = error, metadata, started) do
    Events.emit(
      :music,
      :import,
      :retryable,
      Map.merge(metadata, %{reason: :storage_unavailable, failure_stage: :import}),
      %{duration_ms: Events.elapsed(started)}
    )

    error
  end

  defp stale(metadata, started) do
    Events.emit(:music, :import, :stale, Map.put(metadata, :reason, :stale_observation), %{
      duration_ms: Events.elapsed(started)
    })

    :ok
  end
end
