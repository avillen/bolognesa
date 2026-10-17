defmodule Bolognesa.Series.Application.UseCases.IdentifySeriesFile do
  @moduledoc "Identifies a complete episode selection with external I/O outside transactions."
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
    case repository.begin_identification(id, token, job_id) do
      {:ok, :stale} ->
        :ok

      {:ok, %{content_type: :series} = file} ->
        identify(id, token, attempt, repository, provider, file)

      {:ok, _} ->
        {:error, :wrong_content_type}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp identify(id, token, attempt, repository, provider, file) do
    with {:ok, hint} <- EpisodeHint.from_path(file.relative_path),
         {:ok, candidates} <- provider.search(hint.title, hint.year) do
      identify_candidates(
        id,
        token,
        attempt,
        repository,
        provider,
        hint,
        Enum.take(candidates, 5)
      )
    else
      {:error, reason} -> handle_error(id, token, attempt, repository, [], reason)
    end
  end

  defp identify_candidates(id, token, attempt, repository, provider, hint, candidates) do
    with {:ok, candidate} <- SeriesMatch.select(hint, candidates),
         {:ok, series} <- provider.details(candidate.provider_id),
         true <- series.provider_id == candidate.provider_id,
         {:ok, season} <- provider.season(candidate.provider_id, hint.season_number),
         true <- season.number == hint.season_number,
         {:ok, selection} <- EpisodeSelection.new(series, season, hint.episode_numbers) do
      normalize(repository.complete_series(id, token, candidates, selection, nil))
    else
      false -> handle_error(id, token, attempt, repository, candidates, :invalid_response)
      {:error, reason} -> handle_error(id, token, attempt, repository, candidates, reason)
    end
  end

  defp handle_error(id, token, attempt, repository, candidates, reason) do
    case IdentificationPolicy.failure_action(reason, attempt) do
      {:review, reason} ->
        normalize(repository.complete_series(id, token, candidates, nil, reason))

      {:retry, reason} ->
        {:error, reason}

      {:fail, reason} ->
        normalize(repository.fail(id, token, reason))
    end
  end

  defp normalize({:ok, :stale}), do: :ok
  defp normalize(result), do: result
end
