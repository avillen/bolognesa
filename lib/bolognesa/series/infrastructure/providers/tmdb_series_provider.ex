defmodule Bolognesa.Series.Infrastructure.Providers.TmdbSeriesProvider do
  @moduledoc "TMDb series adapter with bounded shared transport."
  @behaviour Bolognesa.Series.Application.Ports.Providers.SeriesProvider
  alias Bolognesa.Series.Application.Ports.Providers.SeriesProvider
  alias Bolognesa.Series.Domain.ValueObjects.SeasonDetails
  alias Bolognesa.Series.Domain.ValueObjects.SeriesCandidate
  alias Bolognesa.Series.Domain.ValueObjects.SeriesDetails
  alias Bolognesa.Series.Infrastructure.Providers.TmdbClient
  alias Bolognesa.Series.Infrastructure.Providers.TmdbSeriesResponse

  @impl true
  def search(query, year), do: search(query, year, [])

  @spec search(binary(), integer() | nil, keyword()) ::
          {:ok, [SeriesCandidate.t()]} | {:error, SeriesProvider.reason()}
  def search(query, year, opts) do
    params = [query: query, language: "es-ES", include_adult: false, page: 1]

    params =
      if is_integer(year), do: Keyword.put(params, :first_air_date_year, year), else: params

    with {:ok, body} <- TmdbClient.get("/search/tv", params, opts),
         do: TmdbSeriesResponse.search(body)
  end

  @impl true
  def details(id), do: details(id, [])

  @spec details(pos_integer(), keyword()) ::
          {:ok, SeriesDetails.t()} | {:error, SeriesProvider.reason()}
  def details(id, opts) do
    with {:ok, body} <- TmdbClient.get("/tv/#{id}", [language: "es-ES"], opts),
         {:ok, details} <- TmdbSeriesResponse.details(body) do
      if details.provider_id == id, do: {:ok, details}, else: {:error, :invalid_response}
    end
  end

  @impl true
  def season(id, number), do: season(id, number, [])

  @spec season(pos_integer(), non_neg_integer(), keyword()) ::
          {:ok, SeasonDetails.t()} | {:error, SeriesProvider.reason()}
  def season(id, number, opts) do
    with {:ok, body} <- TmdbClient.get("/tv/#{id}/season/#{number}", [language: "es-ES"], opts),
         do: TmdbSeriesResponse.season(body, id, number)
  end
end
