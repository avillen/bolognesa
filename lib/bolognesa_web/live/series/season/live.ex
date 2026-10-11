defmodule BolognesaWeb.Series.Season.Live do
  @moduledoc false
  use BolognesaWeb, :live_view
  alias BolognesaWeb.Series.Season.Reducer
  @impl true
  def mount(_params, _session, socket), do: {:ok, Reducer.Initialize.call(socket)}
  @impl true
  def handle_params(%{"id" => text} = params, _uri, socket) do
    id = parse(text, 0)
    page = parse(Map.get(params, "page", "1"), 1)
    {:noreply, Reducer.Load.call(socket, id, page)}
  end

  @impl true
  def handle_event("retry", _params, socket),
    do: {:noreply, Reducer.Load.call(socket, socket.assigns.content_id, socket.assigns.page)}

  @impl true
  def handle_async({:season_episodes, request}, result, socket),
    do: {:noreply, Reducer.ApplyResult.call(socket, request, result)}

  defp parse(text, default) when is_binary(text) do
    case Integer.parse(text) do
      {id, ""} when id > 0 -> id
      _ -> default
    end
  end

  defp parse(_, default), do: default
end
