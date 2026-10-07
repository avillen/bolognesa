defmodule BolognesaWeb.Movie.Index.Live do
  use BolognesaWeb, :live_view
  alias Bolognesa.Catalog

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:query, "")
     |> assign(:page, 1)
     |> assign(:total, 0)
     |> assign(:loading?, true)
     |> assign(:error, nil)
     |> assign(:request_id, nil)
     |> assign(:form, to_form(%{"q" => ""}, as: :search))
     |> stream(:movies, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = Map.get(params, "q", "")
    page = parse_page(Map.get(params, "page", "1"))
    actor = socket.assigns.current_scope.actor
    request_id = make_ref()

    socket =
      socket
      |> assign(:query, query)
      |> assign(:page, page)
      |> assign(:loading?, true)
      |> assign(:error, nil)
      |> assign(:request_id, request_id)
      |> assign(:form, to_form(%{"q" => query}, as: :search))
      |> start_async({:movies, request_id}, fn -> Catalog.list_movies(actor, query, page) end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"search" => %{"q" => query}}, socket) do
    {:noreply, push_patch(socket, to: ~p"/movies?#{%{q: query}}")}
  end

  @impl true
  def handle_async({:movies, request_id}, result, socket) do
    if socket.assigns.request_id == request_id do
      case result do
        {:ok, {:ok, %{items: items, total: total}}} ->
          {:noreply,
           socket
           |> assign(:loading?, false)
           |> assign(:total, total)
           |> stream(:movies, items, reset: true)}

        _ ->
          {:noreply,
           socket |> assign(:loading?, false) |> assign(:error, "No se pudo cargar el catálogo.")}
      end
    else
      {:noreply, socket}
    end
  end

  defp parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {page, ""} when page > 0 and page <= 100_000 -> page
      _ -> 1
    end
  end

  defp parse_page(_), do: 1
end
