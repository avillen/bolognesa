defmodule Bolognesa.Series.Application.UseCases.SearchSeriesCandidates do
  @moduledoc "Authorize a bounded manual series search."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Series.Application.Ports.Providers.SeriesProvider
  alias Bolognesa.Series.Domain.ValueObjects.SeriesCandidate

  @spec call(AuthenticatedUser.t(), binary(), SeriesProvider.adapter()) ::
          {:ok, [SeriesCandidate.t()]}
          | {:error, :forbidden | :invalid_query | SeriesProvider.reason()}
  def call(actor, query, provider) do
    with :ok <- Accounts.authorize(actor, :admin),
         :ok <- validate(query) do
      result = provider.search(String.trim(query), nil)
      observe(result, actor.id)
      result
    end
  end

  defp validate(query) when is_binary(query) do
    if String.valid?(query) and byte_size(query) <= 256 and String.trim(query) != "",
      do: :ok,
      else: {:error, :invalid_query}
  end

  defp validate(_), do: {:error, :invalid_query}

  defp observe({:error, reason}, user_id),
    do:
      Events.emit(:series, :provider, :failed, %{
        user_id: user_id,
        reason: reason,
        operation: :search,
        failure_stage: :search
      })

  defp observe(_result, _user_id), do: :ok
end
