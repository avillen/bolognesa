defmodule BolognesaWeb.Series.Season.Live do
  @moduledoc false
  use BolognesaWeb, :live_view
  alias BolognesaWeb.Params
  alias BolognesaWeb.Series.Navigation
  alias BolognesaWeb.Series.Season.Components.EpisodeCard
  alias BolognesaWeb.Series.Season.Components.SeasonWatchedAction
  alias BolognesaWeb.Series.Season.Reducer.ApplyResult
  alias BolognesaWeb.Series.Season.Reducer.Initialize
  alias BolognesaWeb.Series.Season.Reducer.Load
  alias BolognesaWeb.Series.Season.Reducer.MarkSeasonWatchedCoordinator
  @impl true
  def mount(_params, _session, socket), do: {:ok, Initialize.call(socket)}
  @impl true
  def handle_params(%{"id" => text} = params, _uri, socket) do
    id = parse(text, 0)
    page = parse(Map.get(params, "page", "1"), 1)
    socket = Navigation.assign_context(socket, params)
    {:noreply, Load.call(socket, id, page)}
  end

  @impl true
  def handle_event("retry", _params, socket),
    do: {:noreply, Load.call(socket, socket.assigns.content_id, socket.assigns.page)}

  def handle_event("mark_season_watched", _params, socket),
    do: {:noreply, MarkSeasonWatchedCoordinator.call(socket)}

  @impl true
  def handle_async({:season_episodes, request}, result, socket),
    do: {:noreply, ApplyResult.call(socket, request, result)}

  defp parse(text, default), do: Params.positive_integer(text) || default
end
