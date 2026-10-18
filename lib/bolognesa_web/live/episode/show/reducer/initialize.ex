defmodule BolognesaWeb.Episode.Show.Reducer.Initialize do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [stream: 3, start_async: 3]
  alias Bolognesa.Series

  alias BolognesaWeb.LiveSupport.PlaybackState

  @spec call(
          Phoenix.LiveView.Socket.t(),
          Bolognesa.Accounts.Domain.Entities.AuthenticatedUser.t(),
          integer()
        ) ::
          Phoenix.LiveView.Socket.t()
  def call(socket, actor, id) do
    request_id = make_ref()

    socket
    |> assign(:content_ref, {:episode, id})
    |> assign(:multi_episode?, false)
    |> assign(:detail, nil)
    |> assign(:loading?, true)
    |> assign(:error, nil)
    |> PlaybackState.initialize()
    |> assign(:request_id, request_id)
    |> stream(:versions, [])
    |> start_async({:episode, request_id}, fn -> Series.fetch_episode(actor, id) end)
  end
end
