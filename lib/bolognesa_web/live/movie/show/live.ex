defmodule BolognesaWeb.Movie.Show.Live do
  @moduledoc false
  # Capability reports are untrusted; only sanitized playback diagnostics may be logged.
  use BolognesaWeb, {:live_view, log: false}
  alias BolognesaWeb.LiveSupport.PlaybackEvents
  alias BolognesaWeb.MediaComponents
  alias BolognesaWeb.Movie.Show.Components.VersionCard
  alias BolognesaWeb.Movie.Show.Reducer.ApplyResult
  alias BolognesaWeb.Movie.Show.Reducer.Initialize
  alias BolognesaWeb.Player
  @impl true
  def mount(%{"id" => id}, _session, socket),
    do: {:ok, Initialize.call(socket, socket.assigns.current_scope.actor, parse_id(id))}

  @impl true
  def handle_async({:movie, request_id}, result, socket),
    do: {:noreply, ApplyResult.call(socket, request_id, result)}

  @impl true
  def handle_event(event, params, socket), do: PlaybackEvents.handle_event(event, params, socket)
  @impl true
  def handle_info(message, socket), do: PlaybackEvents.handle_info(message, socket)
  @impl true
  def terminate(reason, socket), do: PlaybackEvents.terminate(reason, socket)

  defp parse_id(text) do
    case Integer.parse(text) do
      {id, ""} when id > 0 -> id
      _ -> 0
    end
  end
end
