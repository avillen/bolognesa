defmodule Bolognesa.Identification.Application.UseCases.IdentifyMovieFile do
  @moduledoc "Identify a pending file, with provider I/O outside database transactions."
  alias Bolognesa.Identification.Application.Ports.Providers.MovieProvider
  alias Bolognesa.Identification.Application.Ports.Repositories.IdentificationRepository
  alias Bolognesa.Identification.Domain.Entities.Identification
  alias Bolognesa.Identification.Domain.ValueObjects.Movies.TitleHint

  @transient [:rate_limited, :provider_unavailable]

  @spec call(
          pos_integer(),
          Identification.token(),
          pos_integer(),
          IdentificationRepository.adapter(),
          MovieProvider.adapter(),
          integer() | nil
        ) :: :ok | {:error, :unavailable | :unusable_name | MovieProvider.reason()}
  def call(file_id, token, attempt, repository, provider, job_id \\ nil) do
    case repository.begin_identification(file_id, token, job_id) do
      {:ok, :stale} -> :ok
      {:error, :unavailable} -> {:error, :unavailable}
      {:ok, %{content_type: :series}} -> {:error, :wrong_content_type}
      {:ok, file} -> identify(file_id, token, attempt, repository, provider, file)
    end
  end

  defp identify(file_id, token, attempt, repository, provider, file) do
    with {:ok, hint} <- TitleHint.from_path(file.relative_path),
         {:ok, candidates} <- provider.search(hint.title, hint.year) do
      case candidates do
        [] ->
          normalize(repository.complete(file_id, token, [], nil, true))

        [candidate | _] ->
          identify_candidate(
            file_id,
            token,
            attempt,
            repository,
            provider,
            hint,
            candidate,
            candidates
          )
      end
    else
      {:error, reason} -> handle_error(file_id, token, reason, attempt, repository)
    end
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
          repository.complete(file_id, token, candidates, details, review?(hint, candidate))
        )

      {:error, reason} ->
        handle_error(file_id, token, reason, attempt, repository)
    end
  end

  defp review?(hint, candidate) do
    normalize_title(hint.title) != normalize_title(candidate.title) or
      (not is_nil(hint.year) and not is_nil(candidate.year) and hint.year != candidate.year)
  end

  defp normalize_title(title),
    do:
      title
      |> String.downcase()
      |> String.normalize(:nfd)
      |> String.replace(~r/\p{Mn}/u, "")
      |> String.replace(~r/[^a-z0-9]/u, "")

  defp handle_error(file_id, token, reason, attempt, repository) do
    safe_reason =
      if reason in [
           :unusable_name,
           :not_configured,
           :rate_limited,
           :provider_unavailable,
           :unauthorized,
           :invalid_response,
           :not_found
         ], do: reason, else: :provider_unavailable

    if safe_reason in @transient and attempt < 3 do
      {:error, safe_reason}
    else
      case repository.fail(file_id, token, safe_reason) do
        :ok -> :ok
        {:ok, :stale} -> :ok
        {:error, :unavailable} -> {:error, :unavailable}
      end
    end
  end

  defp normalize(:ok), do: :ok
  defp normalize({:ok, :stale}), do: :ok
  defp normalize({:error, :unavailable}), do: {:error, :unavailable}
end
