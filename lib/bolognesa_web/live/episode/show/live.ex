defmodule BolognesaWeb.Episode.Show.Live do
  @moduledoc false
  use BolognesaWeb, :live_view
  alias BolognesaWeb.Episode.Show.Reducer
  alias BolognesaWeb.LiveSupport.PlaybackEvents
  @impl true
  def mount(%{"id" => id}, _session, socket),
    do: {:ok, Reducer.Initialize.call(socket, socket.assigns.current_scope.actor, parse_id(id))}

  @impl true
  def handle_async({:episode, request_id}, result, socket),
    do: {:noreply, Reducer.ApplyResult.call(socket, request_id, result)}

  @impl true
  def handle_event(event, params, socket), do: PlaybackEvents.handle_event(event, params, socket)
  @impl true
  def handle_info(message, socket), do: PlaybackEvents.handle_info(message, socket)
  @impl true
  def terminate(_reason, socket), do: PlaybackEvents.terminate(socket)

  defp parse_id(text) do
    case Integer.parse(text) do
      {id, ""} when id > 0 -> id
      _ -> 0
    end
  end
end
