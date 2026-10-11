defmodule Bolognesa.Identification.Application.Ports.Providers.SeriesProvider do
  @moduledoc "Searches series and retrieves bounded season metadata."
  alias Bolognesa.Identification.Domain.ValueObjects.Series.{
    SeasonDetails,
    SeriesCandidate,
    SeriesDetails
  }

  @type adapter :: atom()
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
              {:ok, SeriesDetails.t()} | {:error, reason()}
  @callback season(series_provider_id :: pos_integer(), season_number :: non_neg_integer()) ::
              {:ok, SeasonDetails.t()} | {:error, reason()}
end
