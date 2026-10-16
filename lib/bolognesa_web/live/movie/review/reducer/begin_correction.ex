defmodule BolognesaWeb.Movie.Review.Reducer.BeginCorrection do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 3]
  alias Bolognesa.Movies

  @spec call(Phoenix.LiveView.Socket.t(), pos_integer(), {:tmdb, pos_integer()} | :unidentified) ::
          Phoenix.LiveView.Socket.t()
  def call(socket, file_id, choice) do
    actor = socket.assigns.current_scope.actor
    request_id = make_ref()

    socket
    |> assign(:correction_request_id, request_id)
    |> assign(:saving?, true)
    |> assign(:feedback, nil)
    |> start_async({:correction, request_id}, fn ->
      Movies.correct(actor, file_id, choice)
    end)
  end
end
