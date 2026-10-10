defmodule BolognesaWeb.Movie.Show.Live do
  @moduledoc false
  use BolognesaWeb, :live_view
  alias BolognesaWeb.Movie.Show.Reducer

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_scope.actor
    {:ok, Reducer.Initialize.call(socket, actor, parse_id(id))}
  end

  @impl true
  def handle_async({:movie, request_id}, result, socket) do
    {:noreply, Reducer.ApplyResult.call(socket, request_id, result)}
  end

  @impl true
  def handle_event("play", %{"file_id" => file_id}, socket) do
    {:noreply, Reducer.SelectVersion.call(socket, file_id)}
  end

  def handle_event("playback_error", %{"file_id" => file_id}, socket) do
    {:noreply, Reducer.PlaybackError.call(socket, file_id)}
  end

  defp parse_id(id) do
    case Integer.parse(id) do
      {value, ""} when value > 0 -> value
      _ -> 0
    end
  end
end
