defmodule Bolognesa.Infrastructure.Observability.PlaybackEvents do
  @moduledoc "Fixed Playback event names shared by diagnostic logging and metrics."

  @events [
    [:bolognesa, :playback, :session, :started],
    [:bolognesa, :playback, :session, :closed],
    [:bolognesa, :playback, :session, :exited],
    [:bolognesa, :playback, :liveview, :terminated],
    [:bolognesa, :playback, :hls, :failed],
    [:bolognesa, :playback, :browser, :diagnostic]
  ]

  @spec events() :: [[atom()]]
  def events, do: @events
end
