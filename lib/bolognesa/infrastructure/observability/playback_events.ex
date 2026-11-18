defmodule Bolognesa.Infrastructure.Observability.PlaybackEvents do
  @moduledoc "Fixed Playback event names shared by diagnostic logging and metrics."

  @events [
    [:bolognesa, :playback, :session, :started],
    [:bolognesa, :playback, :session, :closed],
    [:bolognesa, :playback, :session, :exited],
    [:bolognesa, :playback, :session, :preparation],
    [:bolognesa, :playback, :session, :paced],
    [:bolognesa, :playback, :liveview, :terminated],
    [:bolognesa, :playback, :hls, :failed],
    [:bolognesa, :playback, :browser, :diagnostic]
  ]

  @delivery_enums %{
    strategy: [
      :direct,
      :remux,
      :audio_conversion,
      :video_conversion,
      :full_conversion,
      :audio_only,
      :full_transcode
    ],
    transport: [:file, :native_hls, :hls_js]
  }

  @spec sanitize_delivery_metadata(map()) :: map()
  def sanitize_delivery_metadata(metadata) do
    Enum.reduce(@delivery_enums, metadata, fn {key, allowed}, acc ->
      if Map.get(acc, key) in allowed, do: acc, else: Map.delete(acc, key)
    end)
  end

  @spec events() :: [[atom()]]
  def events, do: @events
end
