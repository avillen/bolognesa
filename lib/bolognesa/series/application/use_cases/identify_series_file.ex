defmodule Bolognesa.Series.Application.UseCases.IdentifySeriesFile do
  @moduledoc "Identifies a complete episode selection with external I/O outside transactions."
  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Series.Application.Ports.Providers.SeriesProvider
  alias Bolognesa.Series.Application.Ports.Repositories.IdentificationRepository
  alias Bolognesa.Series.Domain.Policies.SeriesMatch
  alias Bolognesa.Series.Domain.ValueObjects.EpisodeHint
  alias Bolognesa.Series.Domain.ValueObjects.EpisodeSelection

  alias Bolognesa.Series.Domain.Policies.IdentificationPolicy

  @spec call(
          pos_integer(),
          Bolognesa.Series.Domain.Entities.Identification.token(),
          pos_integer(),
          IdentificationRepository.adapter(),
          SeriesProvider.adapter(),
          integer() | nil
        ) ::
          :ok
          | {:error, :unavailable | :rate_limited | :provider_unavailable | :wrong_content_type}
  def call(id, token, attempt, repository, provider, job_id \\ nil) do
    observation = {%{file_id: id, job_id: job_id, attempt: attempt}, Events.started_at()}

    case repository.begin_identification(id, token, job_id) do
      {:ok, :stale} ->
        observe(observation, :stale)
        :ok

      {:ok, %{content_type: :series} = file} ->
        observation = with_revision(observation, file.revision)
        observe(observation, :started)
        identify(observation, id, token, attempt, repository, provider, file)

      {:ok, _} ->
        observe(observation, :rejected, %{reason: :wrong_content_type})
        {:error, :wrong_content_type}

      {:error, reason} ->
        observe(observation, :retryable, %{
          reason: :storage_unavailable,
          failure_stage: :admission
        })

        {:error, reason}
    end
  end

  defp identify(observation, id, token, attempt, repository, provider, file) do
    with {:ok, hint} <- EpisodeHint.from_path(file.relative_path),
         {:ok, candidates} <- provider_result(provider.search(hint.title, hint.year), :search) do
      identify_candidates(
        observation,
        id,
        token,
        attempt,
        repository,
        provider,
        hint,
        Enum.take(candidates, 5)
      )
    else
      {:error, reason, stage} ->
        handle_error(with_stage(observation, stage), id, token, attempt, repository, [], reason)

      {:error, reason} ->
        handle_error(observation, id, token, attempt, repository, [], reason)
    end
  end

  defp identify_candidates(
         observation,
         id,
         token,
         attempt,
         repository,
         provider,
         hint,
         candidates
       ) do
    with {:ok, candidate} <- SeriesMatch.select(hint, candidates),
         {:ok, series} <- provider_result(provider.details(candidate.provider_id), :details),
         :ok <- matching(series.provider_id, candidate.provider_id, :details),
         {:ok, season} <-
           provider_result(provider.season(candidate.provider_id, hint.season_number), :season),
         :ok <- matching(season.number, hint.season_number, :season),
         {:ok, selection} <- EpisodeSelection.new(series, season, hint.episode_numbers) do
      normalize(
        repository.complete_series(id, token, candidates, selection, nil),
        observation,
        :completed,
        %{result: :matched}
      )
    else
      {:error, reason, stage} ->
        handle_error(
          with_stage(observation, stage),
          id,
          token,
          attempt,
          repository,
          candidates,
          reason
        )

      {:error, reason} ->
        handle_error(observation, id, token, attempt, repository, candidates, reason)
    end
  end

  defp handle_error(observation, id, token, attempt, repository, candidates, reason) do
    case IdentificationPolicy.failure_action(reason, attempt) do
      {:review, reason} ->
        normalize(
          repository.complete_series(id, token, candidates, nil, reason),
          observation,
          :completed,
          %{result: if(reason == :no_match, do: :no_match, else: :review), reason: reason}
        )

      {:retry, reason} ->
        observe(observation, :retryable, %{reason: reason})
        {:error, reason}

      {:fail, reason} ->
        normalize(repository.fail(id, token, reason), observation, :failed, %{reason: reason})
    end
  end

  defp normalize(:ok, observation, outcome, metadata) do
    observe(observation, outcome, metadata)
    :ok
  end

  defp normalize({:ok, :stale}, observation, _outcome, _metadata) do
    observe(observation, :stale)
    :ok
  end

  defp normalize({:error, _reason} = result, observation, _outcome, _metadata) do
    observe(observation, :retryable, %{reason: :storage_unavailable, failure_stage: :persistence})
    result
  end

  defp observe({metadata, started}, outcome, additional \\ %{}) do
    Events.emit(:series, :identification, outcome, Map.merge(metadata, additional), %{
      duration_ms: Events.elapsed(started)
    })
  end

  defp with_revision({metadata, started}, revision),
    do: {Map.put(metadata, :revision, revision), started}

  defp with_stage({metadata, started}, stage),
    do: {Map.put(metadata, :failure_stage, stage), started}

  defp matching(value, value, _stage), do: :ok
  defp matching(_, _, stage), do: {:error, :invalid_response, stage}

  defp provider_result({:error, reason}, stage), do: {:error, reason, stage}
  defp provider_result(result, _stage), do: result
end
