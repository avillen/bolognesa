defmodule Bolognesa.Series.Application.Ports.Providers.SeriesProvider do
  @moduledoc "Searches series and retrieves bounded season metadata."
  alias Bolognesa.Series.Domain.ValueObjects.ProviderSeason
  alias Bolognesa.Series.Domain.ValueObjects.ProviderSeries
  alias Bolognesa.Series.Domain.ValueObjects.SeriesCandidate

  @type adapter :: module()
  @type reason ::
          :not_configured
          | :rate_limited
          | :provider_unavailable
          | :unauthorized
          | :invalid_response
          | :not_found
  @callback search(query :: binary(), first_year :: integer() | nil) ::
              {:ok, [SeriesCandidate.t()]} | {:error, reason()}
  @callback details(series_provider_id :: pos_integer()) ::
              {:ok, ProviderSeries.t()} | {:error, reason()}
  @callback season(series_provider_id :: pos_integer(), season_number :: non_neg_integer()) ::
              {:ok, ProviderSeason.t()} | {:error, reason()}
end
