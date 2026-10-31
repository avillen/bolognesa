defmodule BolognesaWeb.Episode.Show.Reducer.Initialize do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 3]
  alias Bolognesa.Series

  alias BolognesaWeb.LiveSupport.PlaybackState

  @spec call(
          Phoenix.LiveView.Socket.t(),
          Bolognesa.Accounts.Domain.Entities.AuthenticatedUser.t(),
          integer()
        ) ::
          Phoenix.LiveView.Socket.t()
  def call(socket, actor, id) do
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
    |> PlaybackState.initialize()
    |> load(actor, id)
  end

  @spec load(
          Phoenix.LiveView.Socket.t(),
          Bolognesa.Accounts.Domain.Entities.AuthenticatedUser.t(),
          integer()
        ) :: Phoenix.LiveView.Socket.t()
  def load(socket, actor, id) do
    request_id = make_ref()

    socket
    |> assign(:requested_episode_id, id)
    |> assign(:loading?, true)
    |> assign(:error, nil)
    |> assign(:advance_request, nil)
    |> assign(:request_id, request_id)
    |> start_async({:episode, request_id}, fn -> Series.fetch_episode(actor, id) end)
  end
end
