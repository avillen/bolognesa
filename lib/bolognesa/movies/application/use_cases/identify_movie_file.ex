defmodule Bolognesa.Movies.Application.UseCases.IdentifyMovieFile do
  @moduledoc "Identify a pending file, with provider I/O outside database transactions."
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
    case repository.begin_identification(file_id, token, job_id) do
      {:ok, :stale} ->
        :ok

      {:error, :unavailable} ->
        {:error, :unavailable}

      {:ok, %{content_type: :movie} = file} ->
        identify(file_id, token, attempt, repository, provider, file)

      {:ok, _file} ->
        {:error, :wrong_content_type}
    end
  end

  defp identify(file_id, token, attempt, repository, provider, file) do
    with {:ok, hint} <- TitleHint.from_path(file.relative_path),
         {:ok, candidates} <- provider.search(hint.title, hint.year) do
      identify_candidates(file_id, token, attempt, repository, provider, hint, candidates)
    else
      {:error, reason} -> handle_error(file_id, token, reason, attempt, repository)
    end
  end

  defp identify_candidates(file_id, token, _attempt, repository, _provider, _hint, []) do
    normalize(repository.complete(file_id, token, [], nil, true))
  end

  defp identify_candidates(
         file_id,
         token,
         attempt,
         repository,
         provider,
         hint,
         [candidate | _] = candidates
       ) do
    identify_candidate(file_id, token, attempt, repository, provider, hint, candidate, candidates)
  end

  defp identify_candidate(
         file_id,
         token,
         attempt,
         repository,
         provider,
         hint,
         candidate,
         candidates
       ) do
    case provider.details(candidate.provider_id) do
      {:ok, details} ->
        normalize(
          repository.complete(
            file_id,
            token,
            candidates,
            details,
            IdentificationPolicy.needs_review?(hint, candidate)
          )
        )

      {:error, reason} ->
        handle_error(file_id, token, reason, attempt, repository)
    end
  end

  defp handle_error(file_id, token, reason, attempt, repository) do
    case IdentificationPolicy.failure_action(reason, attempt) do
      {:retry, safe_reason} -> {:error, safe_reason}
      {:fail, safe_reason} -> normalize(repository.fail(file_id, token, safe_reason))
    end
  end

  defp normalize(:ok), do: :ok
  defp normalize({:ok, :stale}), do: :ok
  defp normalize({:error, :unavailable}), do: {:error, :unavailable}
end
