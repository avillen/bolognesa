defmodule Bolognesa.Identification.Application.SearchSeriesCandidates do
  @moduledoc "Authorize a bounded manual series search."
  alias Bolognesa.Identification.Application.Ports.Providers.SeriesProvider
  alias Bolognesa.Identification.Domain.SeriesCandidate
  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Actor

  @spec call(Actor.t(), binary(), SeriesProvider.adapter()) ::
          {:ok, [SeriesCandidate.t()]}
          | {:error, :forbidden | :invalid_query | SeriesProvider.reason()}
  def call(actor, query, provider) do
    with :ok <- Identity.authorize(actor, :admin),
         :ok <- validate(query),
         do: provider.search(String.trim(query), nil)
  end

  defp validate(query) when is_binary(query) do
    if String.valid?(query) and byte_size(query) <= 256 and String.trim(query) != "",
      do: :ok,
      else: {:error, :invalid_query}
  end

  defp validate(_), do: {:error, :invalid_query}
end
