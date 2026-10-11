defmodule Bolognesa.Test.BlockingSeriesProvider do
  @moduledoc false
  @behaviour Bolognesa.Identification.Application.Ports.Providers.SeriesProvider
  alias Bolognesa.Test.SyntheticSeriesProvider
  @impl true
  def search(query, year), do: SyntheticSeriesProvider.search(query, year)
  @impl true
  def details(id), do: SyntheticSeriesProvider.details(id)
  @impl true
  def season(id, number) do
    send(Process.get(:series_test_owner), {:series_waiting, self()})

    receive do
      :continue -> SyntheticSeriesProvider.season(id, number)
    end
  end
end
