defmodule Bolognesa.Test.SyntheticSeriesProvider do
  @moduledoc false
  @behaviour Bolognesa.Series.Application.Ports.Providers.SeriesProvider
  alias Bolognesa.Series.Domain.ValueObjects.ProviderEpisode
  alias Bolognesa.Series.Domain.ValueObjects.ProviderSeason
  alias Bolognesa.Series.Domain.ValueObjects.ProviderSeries
  alias Bolognesa.Series.Domain.ValueObjects.SeriesCandidate

  @impl true
  def search("Serie", nil), do: {:ok, [%SeriesCandidate{provider_id: 201, title: "Serie"}]}

  def search("Ambigua", _),
    do:
      {:ok,
       [
         %SeriesCandidate{provider_id: 201, title: "Ambigua"},
         %SeriesCandidate{provider_id: 202, title: "Ambigua"}
       ]}

  def search("Sin coincidencia", _), do: {:ok, []}
  def search(_, _), do: {:error, :provider_unavailable}
  @impl true
  def details(id), do: {:ok, %ProviderSeries{provider_id: id, title: "Serie"}}
  @impl true
  def season(404, _number), do: {:error, :not_found}
  def season(503, _number), do: {:error, :provider_unavailable}

  def season(id, number),
    do:
      {:ok,
       %ProviderSeason{
         provider_id: id * 10 + number,
         series_provider_id: id,
         number: number,
         episodes: [
           %ProviderEpisode{
             provider_id: id * 100 + number * 10 + 1,
             season_number: number,
             number: 1,
             title: "Uno"
           },
           %ProviderEpisode{
             provider_id: id * 100 + number * 10 + 2,
             season_number: number,
             number: 2,
             title: "Dos"
           }
         ]
       }}
end
