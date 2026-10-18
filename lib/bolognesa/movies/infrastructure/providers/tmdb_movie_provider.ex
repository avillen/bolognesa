defmodule Bolognesa.Movies.Infrastructure.Providers.TmdbMovieProvider do
  @moduledoc "TMDb v3 adapter using bounded Req requests."
  @behaviour Bolognesa.Movies.Application.Ports.Providers.MovieProvider

  alias Bolognesa.Infrastructure.Providers.TmdbClient
  alias Bolognesa.Movies.Infrastructure.Providers.TmdbMovieResponse

  @impl true
  def search(query, year), do: search(query, year, [])

  @spec search(binary(), integer() | nil, keyword()) ::
          {:ok, [Bolognesa.Movies.Domain.ValueObjects.MovieCandidate.t()]}
          | {:error, Bolognesa.Movies.Application.Ports.Providers.MovieProvider.reason()}
  def search(query, year, opts) when is_binary(query) do
    params = [query: query, language: "es-ES", include_adult: false, page: 1]
    params = if is_integer(year), do: Keyword.put(params, :year, year), else: params

    with {:ok, body} <- TmdbClient.get("/search/movie", params, opts) do
      TmdbMovieResponse.search(body)
    end
  end

  @impl true
  def details(id), do: details(id, [])

  @spec details(pos_integer(), keyword()) ::
          {:ok, Bolognesa.Movies.Domain.ValueObjects.MovieDetails.t()}
          | {:error, Bolognesa.Movies.Application.Ports.Providers.MovieProvider.reason()}
  def details(id, opts) when is_integer(id) and id > 0 do
    with {:ok, body} <- TmdbClient.get("/movie/#{id}", [language: "es-ES"], opts),
         {:ok, details} <- TmdbMovieResponse.details(body) do
      validate_details(details, id)
    end
  end

  defp validate_details(%{provider_id: id} = details, id), do: {:ok, details}
  defp validate_details(_details, _id), do: {:error, :invalid_response}
end
