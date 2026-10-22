defmodule Bolognesa.Movies.Application.UseCases.IdentifyMovieFile do
  @moduledoc "Identify a pending file, with provider I/O outside database transactions."
  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Movies.Application.Ports.Providers.MovieProvider
  alias Bolognesa.Movies.Application.Ports.Repositories.IdentificationRepository
  alias Bolognesa.Movies.Domain.Entities.Identification
  alias Bolognesa.Movies.Domain.ValueObjects.TitleHint

  alias Bolognesa.Movies.Domain.Policies.IdentificationPolicy

  @spec call(
          pos_integer(),
          Identification.token(),
          pos_integer(),
          IdentificationRepository.adapter(),
          MovieProvider.adapter(),
          integer() | nil
        ) ::
          :ok
          | {:error, :unavailable | :wrong_content_type | :unusable_name | MovieProvider.reason()}
  def call(file_id, token, attempt, repository, provider, job_id \\ nil) do
    observation = {%{file_id: file_id, job_id: job_id, attempt: attempt}, Events.started_at()}

    case repository.begin_identification(file_id, token, job_id) do
      {:ok, :stale} ->
        observe(observation, :stale)
        :ok

      {:error, :unavailable} ->
        observe(observation, :retryable, %{
          reason: :storage_unavailable,
          failure_stage: :admission
        })

        {:error, :unavailable}

      {:ok, %{content_type: :movie} = file} ->
        observation = with_revision(observation, file.revision)
        observe(observation, :started)
        identify(observation, file_id, token, attempt, repository, provider, file)

      {:ok, _file} ->
        observe(observation, :rejected, %{reason: :wrong_content_type})
        {:error, :wrong_content_type}
    end
  end

  defp identify(observation, file_id, token, attempt, repository, provider, file) do
    with {:ok, hint} <- TitleHint.from_path(file.relative_path),
         {:ok, candidates} <- provider_result(provider.search(hint.title, hint.year), :search) do
      identify_candidates(
        observation,
        file_id,
        token,
        attempt,
        repository,
        provider,
        hint,
        candidates
      )
    else
      {:error, reason, stage} ->
        handle_error(with_stage(observation, stage), file_id, token, reason, attempt, repository)

      {:error, reason} ->
        handle_error(observation, file_id, token, reason, attempt, repository)
    end
  end

  defp identify_candidates(
         observation,
         file_id,
         token,
         _attempt,
         repository,
         _provider,
         _hint,
         []
       ) do
    normalize(repository.complete(file_id, token, [], nil, true), observation, :completed, %{
      result: :no_match
    })
  end

  defp identify_candidates(
         observation,
         file_id,
         token,
         attempt,
         repository,
         provider,
         hint,
         [candidate | _] = candidates
       ) do
    case provider_result(provider.details(candidate.provider_id), :details) do
      {:ok, details} ->
        normalize(
          repository.complete(
            file_id,
            token,
            candidates,
            details,
            IdentificationPolicy.needs_review?(hint, candidate)
          ),
          observation,
          :completed,
          %{
            result:
              if(IdentificationPolicy.needs_review?(hint, candidate), do: :review, else: :matched)
          }
        )

      {:error, reason, stage} ->
        handle_error(with_stage(observation, stage), file_id, token, reason, attempt, repository)
    end
  end

  defp handle_error(observation, file_id, token, reason, attempt, repository) do
    case IdentificationPolicy.failure_action(reason, attempt) do
      {:retry, safe_reason} ->
        observe(observation, :retryable, %{reason: safe_reason})
        {:error, safe_reason}

      {:fail, safe_reason} ->
        normalize(repository.fail(file_id, token, safe_reason), observation, :failed, %{
          reason: safe_reason
        })
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
    Events.emit(:movies, :identification, outcome, Map.merge(metadata, additional), %{
      duration_ms: Events.elapsed(started)
    })
  end

  defp with_revision({metadata, started}, revision),
    do: {Map.put(metadata, :revision, revision), started}

  defp with_stage({metadata, started}, stage),
    do: {Map.put(metadata, :failure_stage, stage), started}

  defp provider_result({:error, reason}, stage), do: {:error, reason, stage}
  defp provider_result(result, _stage), do: result
end
