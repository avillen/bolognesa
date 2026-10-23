defmodule Bolognesa.Infrastructure.Observability.PlaybackMetrics do
  @moduledoc "Bounded Playback diagnostic breakdowns alongside the unchanged event counters."

  use PromEx.Plugin

  @diagnostics [
    :mounted,
    :controls,
    :disconnected,
    :reconnected,
    :visibility,
    :error,
    :waiting,
    :recovered,
    :pagehide,
    :pageshow,
    :online,
    :offline,
    :socket_open,
    :socket_closed,
    :socket_error,
    :destroyed,
    :progress,
    :restored,
    :restore_failed,
    :autoplay_blocked
  ]
  @close_reasons [
    :version_selected,
    :seek,
    :ended,
    :client_error,
    :preparation_timeout,
    :source_invalidated,
    :liveview_terminated,
    :owner_terminated,
    :session_replaced,
    :logout,
    :idle_timeout,
    :storage_limit,
    :ffmpeg_failed,
    :process_missing,
    :shutdown,
    :operator_stop
  ]

  @impl true
  def event_metrics(_opts) do
    Event.build(:bolognesa_playback_diagnostic_metrics, [
      counter("bolognesa.playback.browser.observations.total",
        event_name: [:bolognesa, :playback, :browser, :diagnostic],
        tags: [:diagnostic],
        tag_values: fn metadata -> %{diagnostic: bounded(metadata[:diagnostic], @diagnostics)} end
      ),
      counter("bolognesa.playback.ffmpeg.exits.total",
        event_name: [:bolognesa, :playback, :session, :exited],
        tags: [:result],
        tag_values: fn metadata -> %{result: bounded(metadata[:reason], [:finished, :failed])} end
      ),
      counter("bolognesa.playback.session.closures.total",
        event_name: [:bolognesa, :playback, :session, :closed],
        tags: [:reason],
        tag_values: fn metadata -> %{reason: bounded(metadata[:reason], @close_reasons)} end
      )
    ])
  end

  defp bounded(value, allowed) do
    if value in allowed, do: value, else: :other
  end
end
