defmodule BolognesaWeb.Movie.Index.Reducer do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [stream: 4, start_async: 3]
  alias Bolognesa.Catalog

  def load(socket, query, page) do
    actor = socket.assigns.current_scope.actor
    request_id = make_ref()

    socket
    |> assign(:query, query)
    |> assign(:page, page)
    |> assign(:loading?, true)
    |> assign(:error, nil)
    |> assign(:request_id, request_id)
    |> assign(:form, to_form(%{"query" => query}, as: :search))
    |> start_async({:movies, request_id}, fn -> Catalog.list_movies(actor, query, page) end)
  end

  def result(socket, request_id, result) do
    if socket.assigns.request_id == request_id do
      case result do
        {:ok, {:ok, %{items: items, total: total}}} ->
          socket
          |> assign(:loading?, false)
          |> assign(:total, total)
          |> stream(:movies, items, reset: true)

        _ ->
          socket |> assign(:loading?, false) |> assign(:error, "No se pudo cargar el catálogo.")
      end
    else
      socket
    end
  end
end
