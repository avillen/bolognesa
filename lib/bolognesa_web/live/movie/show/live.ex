defmodule BolognesaWeb.Movie.Show.Live do
  use BolognesaWeb, :live_view
  alias Bolognesa.Catalog

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_scope.actor
    request_id = make_ref()

    {:ok,
     socket
     |> assign(:movie, nil)
     |> assign(:loading?, true)
     |> assign(:error, nil)
     |> assign(:request_id, request_id)
     |> stream(:versions, [])
     |> start_async({:movie, request_id}, fn -> Catalog.get_movie(actor, parse_id(id)) end)}
  end

  @impl true
  def handle_async({:movie, request_id}, result, socket) do
    if socket.assigns.request_id == request_id do
      case result do
        {:ok, {:ok, movie}} ->
          {:noreply,
           socket
           |> assign(:loading?, false)
           |> assign(:movie, movie)
           |> stream(:versions, movie.versions, reset: true)}

        _ ->
          {:noreply,
           socket |> assign(:loading?, false) |> assign(:error, "No se encontró la película.")}
      end
    else
      {:noreply, socket}
    end
  end

  defp parse_id(id) do
    case Integer.parse(id) do
      {value, ""} when value > 0 -> value
      _ -> 0
    end
  end
end
