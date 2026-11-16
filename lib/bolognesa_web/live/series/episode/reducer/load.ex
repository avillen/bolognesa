defmodule BolognesaWeb.Series.Episode.Reducer.Load do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 3]
  alias Bolognesa.Series

  @spec call(
          Phoenix.LiveView.Socket.t(),
          Bolognesa.Accounts.Domain.Entities.AuthenticatedUser.t(),
          integer()
        ) :: Phoenix.LiveView.Socket.t()
  def call(socket, actor, id) do
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
