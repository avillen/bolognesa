defmodule BolognesaWeb.Series.Show.Live do
  @moduledoc false
  use BolognesaWeb, :live_view
  alias BolognesaWeb.MediaComponents
  alias BolognesaWeb.Params
  alias BolognesaWeb.Series.Navigation
  alias BolognesaWeb.Series.Show.Components.SeasonCard
  alias BolognesaWeb.Series.Show.Components.SeriesHero
  alias BolognesaWeb.Series.Show.Reducer.ApplyContinueTarget
  alias BolognesaWeb.Series.Show.Reducer.ApplyResult
  alias BolognesaWeb.Series.Show.Reducer.Initialize
  alias BolognesaWeb.Series.Show.Reducer.Load
  alias BolognesaWeb.Series.Show.Reducer.LoadContinueTarget
  @impl true
  def mount(_params, _session, socket), do: {:ok, Initialize.call(socket)}
  @impl true
  def handle_params(%{"id" => text} = params, _uri, socket) do
    id = parse(text, 0)
    page = parse(Map.get(params, "page", "1"), 1)
    socket = Navigation.assign_context(socket, params)
    {:noreply, socket |> Load.call(id, page) |> LoadContinueTarget.call(id)}
  end

  @impl true
  def handle_event("retry", _params, socket),
    do:
      {:noreply,
       socket
       |> Load.call(socket.assigns.content_id, socket.assigns.page)
       |> LoadContinueTarget.call(socket.assigns.content_id)}

  @impl true
  def handle_async({:continue_target, id}, result, socket),
    do: {:noreply, ApplyContinueTarget.call(socket, id, result)}

  def handle_async({:series_detail, request}, result, socket),
    do: {:noreply, ApplyResult.call(socket, request, result)}

  defp parse(text, default), do: Params.positive_integer(text) || default
end
