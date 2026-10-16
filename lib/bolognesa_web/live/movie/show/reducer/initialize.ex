defmodule BolognesaWeb.Movie.Show.Reducer.Initialize do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [stream: 3, start_async: 3]
  alias Bolognesa.Movies

  @spec call(Phoenix.LiveView.Socket.t(), Bolognesa.Accounts.Domain.Entities.Actor.t(), integer()) ::
          Phoenix.LiveView.Socket.t()
  def call(socket, actor, id) do
    request_id = make_ref()

    socket
    |> assign(:content_ref, {:movie, id})
    |> assign(:detail, nil)
    |> assign(:loading?, true)
    |> assign(:error, nil)
    |> assign(:selected_file_id, nil)
    |> assign(:compatible_session, nil)
    |> assign(:compatible_ready?, false)
    |> assign(:compatible_paused?, false)
    |> assign(:compatible_poll_attempts, 0)
    |> assign(:compatible_autoplay?, false)
    |> assign(:playback_error, nil)
    |> assign(:playback_error_reason, nil)
    |> assign(:request_id, request_id)
    |> stream(:versions, [])
    |> start_async({:movie, request_id}, fn -> Movies.get_movie(actor, id) end)
  end
end
