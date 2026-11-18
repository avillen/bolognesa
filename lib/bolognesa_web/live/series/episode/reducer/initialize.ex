defmodule BolognesaWeb.Series.Episode.Reducer.Initialize do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  alias BolognesaWeb.LiveSupport.PlaybackAttempt

  @spec call(Phoenix.LiveView.Socket.t(), integer()) :: Phoenix.LiveView.Socket.t()
  def call(socket, id) do
    socket
    |> assign(:content_ref, {:episode, id})
    |> assign(:multi_episode?, false)
    |> assign(:detail, nil)
    |> assign(:requested_part, nil)
    |> assign(:active_part, nil)
    |> assign(:parts, [])
    |> assign(:part_versions, [])
    |> assign(:playback_versions, [])
    |> assign(:previous_target, nil)
    |> assign(:next_target, nil)
    |> assign(:loading?, true)
    |> assign(:error, nil)
    |> assign(:playback, PlaybackAttempt.new())
  end
end
