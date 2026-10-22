defmodule Bolognesa.Music.Infrastructure.Jobs.RefreshWorker do
  @moduledoc "Bounded durable music import with token and job ownership checks."
  alias Bolognesa.Music.Infrastructure.Jobs.ImportPolicy
  use Oban.Worker, queue: :music_imports, max_attempts: ImportPolicy.max_attempts()

  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Music.Application.Ports.Readers.ObservationsReader
  alias Bolognesa.Music.Application.Ports.Repositories.{ImportRepository, MusicRepository}
  alias Bolognesa.Music.Application.UseCases.RefreshTrack
  alias Bolognesa.Music.Infrastructure.Readers.EctoObservationsReader
  alias Bolognesa.Music.Infrastructure.Repositories.{EctoImportRepository, EctoMusicRepository}

  @impl Oban.Worker
  def timeout(_job), do: ImportPolicy.timeout_ms()

  @impl Oban.Worker
  def perform(job),
    do: perform(job, EctoImportRepository, EctoObservationsReader, EctoMusicRepository)

  @spec perform(
          Oban.Job.t(),
          ImportRepository.adapter(),
          ObservationsReader.adapter(),
          MusicRepository.adapter()
        ) ::
          RefreshTrack.result()
          | {:error, :storage_unavailable | :unexpected_failure}
          | {:cancel, :unexpected_failure}
  def perform(
        %Oban.Job{args: %{"file_id" => id, "revision" => revision}} = job,
        repository,
        reader,
        music_repository
      )
      when is_integer(id) and id > 0 and is_integer(revision) and revision > 0 do
    case repository.begin_attempt(id, revision, job.id) do
      {:ok, :stale} ->
        Events.emit(:music, :import, :stale, Map.put(metadata(job), :reason, :stale_attempt))
        :ok

      {:ok, attempt} ->
        Events.emit(:music, :import, :started, metadata(job))
        refresh(job, attempt, repository, reader, music_repository)

      {:error, :unavailable} ->
        Events.emit(
          :music,
          :import,
          :retryable,
          Map.merge(metadata(job), %{reason: :storage_unavailable, failure_stage: :admission})
        )

        {:error, :storage_unavailable}
    end
  rescue
    _error -> unexpected(job)
  catch
    _kind, _value -> unexpected(job)
  end

  def perform(_job, _repository, _reader, _music_repository), do: {:cancel, :unexpected_failure}

  defp refresh(job, attempt, repository, reader, music_repository) do
    result =
      RefreshTrack.call(
        attempt.media_file_id,
        attempt.observed_revision,
        reader,
        music_repository,
        attempt.inspection_token,
        %{job_id: job.id, attempt: job.attempt}
      )

    if result != :ok && job.attempt >= job.max_attempts do
      observe_exhaustion(repository.fail_attempt(attempt, :storage_unavailable), job)
    end

    result
  end

  defp observe_exhaustion(:ok, job),
    do:
      Events.emit(
        :music,
        :import,
        :failed,
        Map.merge(metadata(job), %{reason: :attempts_exhausted, failure_stage: :exhaustion})
      )

  defp observe_exhaustion({:ok, :stale}, job),
    do:
      Events.emit(
        :music,
        :import,
        :stale,
        Map.merge(metadata(job), %{reason: :stale_attempt, failure_stage: :exhaustion})
      )

  defp observe_exhaustion({:error, :unavailable}, job),
    do:
      Events.emit(
        :music,
        :import,
        :retryable,
        Map.merge(metadata(job), %{reason: :storage_unavailable, failure_stage: :exhaustion})
      )

  defp unexpected(job) do
    Events.emit(
      :music,
      :import,
      :failed,
      Map.merge(metadata(job), %{reason: :unexpected_failure, failure_stage: :import})
    )

    {:error, :unexpected_failure}
  end

  defp metadata(job),
    do: %{
      file_id: job.args["file_id"],
      revision: job.args["revision"],
      job_id: job.id,
      attempt: job.attempt
    }
end
