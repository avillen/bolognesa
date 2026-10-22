defmodule Bolognesa.Movies.Application.UseCases.SearchMovieCandidates do
  @moduledoc "Authorize and validate a manual movie search."
  alias Bolognesa.Accounts
  alias Bolognesa.Infrastructure.Observability.Events

  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Movies.Application.Ports.Providers.MovieProvider
  alias Bolognesa.Movies.Domain.ValueObjects.MovieCandidate

  @spec call(AuthenticatedUser.t(), String.t(), MovieProvider.adapter()) ::
          {:ok, [MovieCandidate.t()]}
          | {:error, :forbidden | :invalid_query | MovieProvider.reason()}
  def call(actor, query, provider) do
    with :ok <- Accounts.authorize(actor, :admin),
         :ok <- valid_query(query) do
      result = provider.search(String.trim(query), nil)
      observe(result, actor.id)
      result
    end
  end

  defp valid_query(query) when is_binary(query) do
    if String.valid?(query) and String.trim(query) != "" and byte_size(query) <= 256,
      do: :ok,
      else: {:error, :invalid_query}
  end

  defp valid_query(_query), do: {:error, :invalid_query}

  defp observe({:error, reason}, user_id),
    do:
      Events.emit(:movies, :provider, :failed, %{
        user_id: user_id,
        reason: reason,
        operation: :search,
        failure_stage: :search
      })

  defp observe(_result, _user_id), do: :ok
end
