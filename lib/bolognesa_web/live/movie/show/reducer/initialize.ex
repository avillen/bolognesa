defmodule BolognesaWeb.Movie.Show.Reducer.Initialize do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 3]
  alias Bolognesa.Movies

  alias BolognesaWeb.LiveSupport.PlaybackAttempt

  @spec call(
          Phoenix.LiveView.Socket.t(),
          Bolognesa.Accounts.Domain.Entities.AuthenticatedUser.t(),
          integer()
        ) ::
          Phoenix.LiveView.Socket.t()
  def call(socket, actor, id) do
    request_id = make_ref()

    socket
    |> assign(:content_ref, {:movie, id})
    |> assign(:watched_attempt_id, nil)
    |> assign(:detail, nil)
    |> assign(:loading?, true)
    |> assign(:error, nil)
    |> assign(:playback, PlaybackAttempt.new())
    |> assign(:request_id, request_id)
    |> start_async({:movie, request_id}, fn -> Movies.get_movie(actor, id) end)
  end
end
