defmodule Bolognesa.Test.DelayedSearchSeriesProvider do
  @moduledoc false
  @behaviour Bolognesa.Identification.Application.Ports.SeriesProvider
  alias Bolognesa.Test.SyntheticSeriesProvider
  @impl true
  def search("Slow", _) do
    send(Application.fetch_env!(:bolognesa, :series_search_test_owner), {:search_started, self()})

    receive do
      :release -> SyntheticSeriesProvider.search("Serie", nil)
    end
  end

  def search(query, year), do: SyntheticSeriesProvider.search(query, year)
  @impl true
  def details(id), do: SyntheticSeriesProvider.details(id)
  @impl true
  def season(id, number), do: SyntheticSeriesProvider.season(id, number)
end
