defmodule BolognesaWeb.Movie.Show.Reducer do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [stream: 3, stream: 4, start_async: 3]
  alias Bolognesa.Catalog

  def load(socket, actor, id) do
    request_id = make_ref()

    socket
    |> assign(:movie, nil)
    |> assign(:loading?, true)
    |> assign(:error, nil)
    |> assign(:request_id, request_id)
    |> stream(:versions, [])
    |> start_async({:movie, request_id}, fn -> Catalog.get_movie(actor, id) end)
  end

  def result(socket, request_id, result) do
    if socket.assigns.request_id == request_id do
      case result do
        {:ok, {:ok, movie}} ->
          socket
          |> assign(:loading?, false)
          |> assign(:movie, movie)
          |> stream(:versions, movie.versions, reset: true)

        _ ->
          socket |> assign(:loading?, false) |> assign(:error, "No se encontró la película.")
      end
    else
      socket
    end
  end
end
