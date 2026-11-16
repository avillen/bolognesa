defmodule BolognesaWeb.Series.Index.Live do
  @moduledoc false
  use BolognesaWeb, :live_view
  alias BolognesaWeb.Params
  alias BolognesaWeb.Series.Index.Components.SeriesCard
  alias BolognesaWeb.Series.Index.Reducer.ApplyResult
  alias BolognesaWeb.Series.Index.Reducer.Initialize
  alias BolognesaWeb.Series.Index.Reducer.Load
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
  def handle_async({:series, request_id}, result, socket) do
    {:noreply, ApplyResult.call(socket, request_id, result)}
  end
end
