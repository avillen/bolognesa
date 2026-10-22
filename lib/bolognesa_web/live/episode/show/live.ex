defmodule BolognesaWeb.Episode.Show.Live do
  @moduledoc false
  use BolognesaWeb, :live_view
  alias BolognesaWeb.Episode.Show.Reducer
  alias BolognesaWeb.LiveSupport.PlaybackEvents
  alias BolognesaWeb.Series.Navigation
  @impl true
  def mount(%{"id" => id}, _session, socket),
    do: {:ok, Reducer.Initialize.call(socket, socket.assigns.current_scope.actor, parse_id(id))}

  @impl true
  def handle_params(params, _uri, socket),
    do: {:noreply, Navigation.assign_context(socket, params)}

  @impl true
  def handle_async({:next_episode, request}, result, socket),
    do: {:noreply, Reducer.Advance.apply_result(socket, request, result)}

  def handle_async({:episode, request_id}, result, socket),
    do: {:noreply, Reducer.ApplyResult.call(socket, request_id, result)}

  @impl true
  def handle_event("playback_ended", params, socket),
    do: {:noreply, Reducer.Advance.call(socket, params)}

  def handle_event(event, params, socket)
      when event in ["play", "playback_seek", "playback_resume", "playback_error"],
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

  defp parse_id(text) do
    case Integer.parse(text) do
      {id, ""} when id > 0 -> id
      _ -> 0
    end
  end
end
