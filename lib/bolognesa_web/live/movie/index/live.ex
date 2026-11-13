defmodule BolognesaWeb.Movie.Index.Live do
  @moduledoc false
  use BolognesaWeb, :live_view
  alias BolognesaWeb.Movie.Index.Reducer.ApplyResult
  alias BolognesaWeb.Movie.Index.Reducer.Initialize
  alias BolognesaWeb.Movie.Index.Reducer.Load

  @impl true
  def mount(_params, _session, socket), do: {:ok, Initialize.call(socket)}

  @impl true
  def handle_params(params, _uri, socket) do
    query = Map.get(params, "query", "")
    page = parse_page(Map.get(params, "page", "1"))
    {:noreply, Load.call(socket, query, page)}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/movies?#{Map.put(socket.assigns.library_params, :query, query)}")}
  end

  @impl true
  def handle_async({:movies, request_id}, result, socket) do
    {:noreply, ApplyResult.call(socket, request_id, result)}
  end

  defp parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {page, ""} when page > 0 and page <= 100_000 -> page
      _ -> 1
    end
  end

  defp parse_page(_), do: 1
end
