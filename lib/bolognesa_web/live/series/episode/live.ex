defmodule BolognesaWeb.Series.Episode.Live do
  @moduledoc false
  # Capability reports are untrusted; only sanitized playback diagnostics may be logged.
  use BolognesaWeb, {:live_view, log: false}
  alias BolognesaWeb.LiveSupport.PlaybackEvents
  alias BolognesaWeb.MediaComponents
  alias BolognesaWeb.Params
  alias BolognesaWeb.Player
  alias BolognesaWeb.Series.Episode.Components.EpisodeNavigation
  alias BolognesaWeb.Series.Episode.Components.VersionCard
  alias BolognesaWeb.Series.Episode.Parts
  alias BolognesaWeb.Series.Episode.Reducer.Advance
  alias BolognesaWeb.Series.Episode.Reducer.ApplyAdvanceResult
  alias BolognesaWeb.Series.Episode.Reducer.ApplyResultCoordinator
  alias BolognesaWeb.Series.Episode.Reducer.Initialize
  alias BolognesaWeb.Series.Episode.Reducer.Load
  alias BolognesaWeb.Series.Episode.Reducer.RecordWatchedEntries
  alias BolognesaWeb.Series.Episode.Reducer.SelectPart
  alias BolognesaWeb.Series.Navigation
  @impl true
  def mount(%{"id" => id}, _session, socket) do
    id = parse_id(id)
    {:ok, socket |> Initialize.call(id) |> Load.call(socket.assigns.current_scope.actor, id)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    id = parse_id(params["id"])
    part = parse_part(Map.get(params, "part"))
    changed = socket.assigns.requested_part != part
    socket = socket |> Navigation.assign_context(params) |> assign(:requested_part, part)

    socket =
      cond do
        socket.assigns.requested_episode_id != id ->
          Load.call(socket, socket.assigns.current_scope.actor, id)

        changed && socket.assigns.detail && !socket.assigns.loading? ->
          SelectPart.call(socket, part)

        true ->
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_async({:next_episode, request}, result, socket),
    do: {:noreply, ApplyAdvanceResult.call(socket, request, result)}

  def handle_async({:episode, request_id}, result, socket),
    do: {:noreply, ApplyResultCoordinator.call(socket, request_id, result)}

  @impl true
  def handle_event("record_watched_entries", params, socket) do
    socket = RecordWatchedEntries.call(socket, params)
    {:reply, %{ok: socket.assigns.watched_attempt_id == params["attempt_id"]}, socket}
  end

  def handle_event("playback_ended", params, socket),
    do: {:noreply, Advance.call(socket, params)}

  def handle_event("play", %{"file_id" => text} = params, socket) do
    version = Enum.find(socket.assigns.playback_versions, &(to_string(&1.id) == text))

    if version do
      {:noreply, updated} = handle_playback_action("play", params, socket)

      updated =
        if updated.assigns.playback.file_id == version.id,
          do: Parts.assign_part(updated, version.part_number),
          else: updated

      {:noreply, updated}
    else
      {:noreply, socket}
    end
  end

  def handle_event(event, params, socket)
      when event in ["playback_seek", "playback_resume", "playback_error"],
      do: handle_playback_action(event, params, socket)

  def handle_event(event, params, socket), do: PlaybackEvents.handle_event(event, params, socket)
  @impl true
  def handle_info(message, socket), do: PlaybackEvents.handle_info(message, socket)
  @impl true
  def terminate(reason, socket), do: PlaybackEvents.terminate(reason, socket)

  defp handle_playback_action(event, params, socket) do
    {:noreply, updated} = PlaybackEvents.handle_event(event, params, socket)

    if updated == socket,
      do: {:noreply, updated},
      else: {:noreply, assign(updated, :advance_request, nil)}
  end

  defp air_date(date) do
    months =
      case Gettext.get_locale(BolognesaWeb.Gettext) do
        "en" -> ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
        _ -> ~w(ene feb mar abr may jun jul ago sep oct nov dic)
      end

    "#{date.day} #{Enum.at(months, date.month - 1)} #{date.year}"
  end

  defp parse_part(nil), do: nil

  defp parse_part(text), do: Params.integer(text, 1..100) || :invalid
  defp parse_id(text), do: Params.positive_integer(text) || 0
end
