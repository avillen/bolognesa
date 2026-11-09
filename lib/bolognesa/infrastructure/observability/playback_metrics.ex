defmodule Bolognesa.Infrastructure.Observability.PlaybackMetrics do
  @moduledoc "Bounded Playback diagnostic breakdowns alongside the unchanged event counters."

  use PromEx.Plugin

  @diagnostics [
    :mounted,
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

  @preparation_stages [:first_progress, :first_segment, :ready, :timeout]
  @duration_buckets [1, 5, 10, 25, 50, 100, 250, 500, 1_000, 5_000, 15_000, 30_000, 60_000]

  @impl true
  def event_metrics(_opts) do
    metrics = [
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
    ]

    Event.build(:bolognesa_playback_diagnostic_metrics, metrics ++ preparation_metrics())
  end

  defp preparation_metrics do
    launch =
      for {name, measurement} <- [
            prelaunch_milliseconds: :prelaunch_ms,
            spawn_milliseconds: :spawn_ms
          ] do
        distribution([:bolognesa, :playback, :session, name],
          event_name: [:bolognesa, :playback, :session, :started],
          measurement: measurement,
          tags: [],
          reporter_options: [buckets: @duration_buckets]
        )
      end

    progress =
      for {name, measurement, buckets} <- [
            {:duration_milliseconds, :duration_ms, @duration_buckets},
            {:published_milliseconds, :published_ms, @duration_buckets},
            {:segments, :segment_count, [0, 1, 2, 3, 5, 10, 30, 100]},
            {:first_progress_milliseconds, :first_progress_ms, @duration_buckets},
            {:progress_age_milliseconds, :progress_age_ms, @duration_buckets},
            {:ffmpeg_frames, :ffmpeg_frame, [0, 1, 24, 100, 500, 1_000, 5_000, 30_000]},
            {:ffmpeg_output_milliseconds, :ffmpeg_output_ms, @duration_buckets},
            {:ffmpeg_speed_milli, :ffmpeg_speed_milli,
             [0, 100, 250, 500, 1_000, 2_000, 5_000, 10_000]}
          ] do
        distribution([:bolognesa, :playback, :preparation, name],
          event_name: [:bolognesa, :playback, :session, :preparation],
          measurement: fn measurements ->
            case measurements[measurement] do
              value when is_number(value) -> value
              _missing -> nil
            end
          end,
          tags: [:stage],
          tag_values: &preparation_tags/1,
          reporter_options: [buckets: buckets]
        )
      end

    observations =
      counter("bolognesa.playback.preparation.observations.total",
        event_name: [:bolognesa, :playback, :session, :preparation],
        tags: [:stage],
        tag_values: &preparation_tags/1
      )

    launch ++ [observations | progress]
  end

  defp preparation_tags(metadata),
    do: %{stage: bounded(metadata[:stage], @preparation_stages)}

  defp bounded(value, allowed) do
    if value in allowed, do: value, else: :other
  end
end
