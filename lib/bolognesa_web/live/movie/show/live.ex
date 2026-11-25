defmodule BolognesaWeb.Movie.Show.Live do
  @moduledoc false
  # Capability reports are untrusted; only sanitized playback diagnostics may be logged.
  use BolognesaWeb, {:live_view, log: false}
  alias Bolognesa.Movies
  alias BolognesaWeb.LiveSupport.PlaybackEvents
  alias BolognesaWeb.LiveSupport.WatchedRecording
  alias BolognesaWeb.MediaComponents
  alias BolognesaWeb.Movie.Show.Components.VersionCard
  alias BolognesaWeb.Movie.Show.Reducer.ApplyResult
  alias BolognesaWeb.Movie.Show.Reducer.Initialize
  alias BolognesaWeb.Movie.Show.Reducer.MarkWatched
  alias BolognesaWeb.Movie.Show.Reducer.UnmarkWatched
  alias BolognesaWeb.Params
  alias BolognesaWeb.Player
  @impl true
  def mount(%{"id" => id}, _session, socket),
    do: {:ok, Initialize.call(socket, socket.assigns.current_scope.actor, parse_id(id))}

  @impl true
  def handle_async({:movie, request_id}, result, socket),
    do: {:noreply, ApplyResult.call(socket, request_id, result)}

  @impl true
  def handle_event("record_watched_entries", params, socket) do
    {:reply, reply, updated} =
      WatchedRecording.handle_event(params, socket, &Movies.record_watched/3)

    # A newly saved attempt means the threshold was crossed now; show it without a reload.
    if updated.assigns.watched_attempt_id != socket.assigns.watched_attempt_id,
      do: {:reply, reply, assign(updated, :watched_at, DateTime.utc_now())},
      else: {:reply, reply, updated}
  end

  def handle_event("mark_watched", _params, socket), do: {:noreply, MarkWatched.call(socket)}

  def handle_event("unmark_watched", _params, socket),
    do: {:noreply, UnmarkWatched.call(socket)}

  def handle_event(event, params, socket), do: PlaybackEvents.handle_event(event, params, socket)
  @impl true
  def handle_info(message, socket), do: PlaybackEvents.handle_info(message, socket)
  @impl true
  def terminate(reason, socket), do: PlaybackEvents.terminate(reason, socket)

  defp parse_id(text), do: Params.positive_integer(text) || 0
end
