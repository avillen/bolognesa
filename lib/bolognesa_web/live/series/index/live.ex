defmodule BolognesaWeb.Series.Index.Live do
  @moduledoc false
  use BolognesaWeb, :live_view
  alias BolognesaWeb.MediaComponents
  alias BolognesaWeb.Params
  alias BolognesaWeb.Series.Components.ContinueLink
  alias BolognesaWeb.Series.Index.Components.SeriesCard
  alias BolognesaWeb.Series.Index.Reducer.ApplyRecentSeries
  alias BolognesaWeb.Series.Index.Reducer.ApplyResult
  alias BolognesaWeb.Series.Index.Reducer.Initialize
  alias BolognesaWeb.Series.Index.Reducer.Load
  alias BolognesaWeb.Series.Index.Reducer.LoadRecentSeries
  alias BolognesaWeb.Series.Navigation

  @impl true
  def mount(_params, _session, socket), do: {:ok, Initialize.call(socket)}

  @impl true
  def handle_params(params, _uri, socket) do
    query = Map.get(params, "query", "")
    page = Params.page(params["page"])

    socket =
      socket
      |> Load.call(query, page)
      |> LoadRecentSeries.call()
      |> Navigation.assign_context(%{
        "catalog_query" => query,
        "catalog_page" => page
      })

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/series?#{Map.put(socket.assigns.library_params, :query, query)}")}
  end

  @impl true
  def handle_async(:recent_series, result, socket),
    do: {:noreply, ApplyRecentSeries.call(socket, result)}

  def handle_async({:series, request_id}, result, socket) do
    {:noreply, ApplyResult.call(socket, request_id, result)}
  end
end
