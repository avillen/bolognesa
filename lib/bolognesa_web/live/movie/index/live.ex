defmodule BolognesaWeb.Movie.Index.Live do
  @moduledoc false
  use BolognesaWeb, :live_view
  alias BolognesaWeb.MediaComponents
  alias BolognesaWeb.Movie.Index.Components.MovieCard
  alias BolognesaWeb.Movie.Index.Reducer.ApplyRecentMovies
  alias BolognesaWeb.Movie.Index.Reducer.ApplyResult
  alias BolognesaWeb.Movie.Index.Reducer.Initialize
  alias BolognesaWeb.Movie.Index.Reducer.Load
  alias BolognesaWeb.Movie.Index.Reducer.LoadRecentMovies
  alias BolognesaWeb.Params

  @impl true
  def mount(_params, _session, socket), do: {:ok, Initialize.call(socket)}

  @impl true
  def handle_params(params, _uri, socket) do
    query = Map.get(params, "query", "")
    page = Params.page(params["page"])
    {:noreply, socket |> Load.call(query, page) |> LoadRecentMovies.call()}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/movies?#{Map.put(socket.assigns.library_params, :query, query)}")}
  end

  @impl true
  def handle_async(:recent_movies, result, socket),
    do: {:noreply, ApplyRecentMovies.call(socket, result)}

  def handle_async({:movies, request_id}, result, socket) do
    {:noreply, ApplyResult.call(socket, request_id, result)}
  end
end
