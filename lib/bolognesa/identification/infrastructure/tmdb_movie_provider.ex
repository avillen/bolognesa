defmodule Bolognesa.Identification.Infrastructure.TmdbMovieProvider do
  @moduledoc "TMDb v3 adapter using bounded Req requests."
  @behaviour Bolognesa.Identification.Application.Ports.MovieProvider

  alias Bolognesa.Identification.Infrastructure.TmdbClient
  alias Bolognesa.Identification.Infrastructure.TmdbResponse

  @impl true
  def search(query, year), do: search(query, year, [])

  @spec search(binary(), integer() | nil, keyword()) ::
          {:ok, [Bolognesa.Identification.Domain.MovieCandidate.t()]}
          | {:error, Bolognesa.Identification.Application.Ports.MovieProvider.reason()}
  def search(query, year, opts) when is_binary(query) do
    params = [query: query, language: "es-ES", include_adult: false, page: 1]
    params = if is_integer(year), do: Keyword.put(params, :year, year), else: params

    with {:ok, body} <- TmdbClient.get("/search/movie", params, opts) do
      TmdbResponse.search(body)
    end
  end

  @impl true
  def details(id), do: details(id, [])

  @spec details(pos_integer(), keyword()) ::
          {:ok, Bolognesa.Identification.Domain.MovieDetails.t()}
          | {:error, Bolognesa.Identification.Application.Ports.MovieProvider.reason()}
  def details(id, opts) when is_integer(id) and id > 0 do
    with {:ok, body} <- TmdbClient.get("/movie/#{id}", [language: "es-ES"], opts),
         {:ok, details} <- TmdbResponse.details(body) do
      if details.provider_id == id, do: {:ok, details}, else: {:error, :invalid_response}
    end
  end
end
