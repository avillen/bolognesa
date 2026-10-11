defmodule Bolognesa.Identification.Application.Ports.Providers.MovieProvider do
  @moduledoc "Searches and retrieves bounded movie metadata."

  alias Bolognesa.Identification.Domain.{MovieCandidate, MovieDetails}

  @type reason ::
          :not_configured
          | :rate_limited
          | :provider_unavailable
          | :unauthorized
          | :invalid_response
          | :not_found

  @type adapter :: atom()

  @callback search(binary(), integer() | nil) :: {:ok, [MovieCandidate.t()]} | {:error, reason()}
  @callback details(pos_integer()) :: {:ok, MovieDetails.t()} | {:error, reason()}
end
