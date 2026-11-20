defmodule Bolognesa.Movies.Application.Ports.Providers.MovieProvider do
  @moduledoc "Searches and retrieves bounded movie metadata."

  alias Bolognesa.Movies.Domain.ValueObjects.MovieCandidate
  alias Bolognesa.Movies.Domain.ValueObjects.ProviderMovie

  @type reason ::
          :not_configured
          | :rate_limited
          | :provider_unavailable
          | :unauthorized
          | :invalid_response
          | :not_found

  @type adapter :: atom()

  @callback search(String.t(), integer() | nil) ::
              {:ok, [MovieCandidate.t()]} | {:error, reason()}
  @callback details(pos_integer()) :: {:ok, ProviderMovie.t()} | {:error, reason()}
end
