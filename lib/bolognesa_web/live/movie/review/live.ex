defmodule BolognesaWeb.Movie.Review.Live do
  use BolognesaWeb, :live_view
  alias Bolognesa.Identification

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page, 1)
      |> assign(:total, 0)
      |> assign(:loading?, true)
      |> assign(:error, nil)
      |> assign(:feedback, nil)
      |> assign(:selected_file_id, nil)
      |> assign(:candidates, [])
      |> assign(:searching?, false)
      |> assign(:request_id, nil)
      |> assign(:search_request_id, nil)
      |> assign(:form, to_form(%{"query" => "", "tmdb_id" => ""}, as: :correction))
      |> stream_configure(:reviews, dom_id: &"review-#{&1.file_id}")
      |> stream(:reviews, [])

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page =
      case Integer.parse(Map.get(params, "page", "1")) do
        {value, ""} when value > 0 and value <= 100_000 -> value
        _ -> 1
      end

    {:noreply, socket |> assign(:page, page) |> load()}
  end

  @impl true
  def handle_event("select", %{"file_id" => id}, socket) do
    case positive_id(id) do
      {:ok, file_id} ->
        {:noreply,
         socket
         |> assign(:selected_file_id, file_id)
         |> assign(:candidates, [])
         |> assign(:feedback, nil)}

      :error ->
        {:noreply, assign(socket, :feedback, "Archivo inválido.")}
    end
  end

  def handle_event("search", %{"correction" => %{"query" => query}}, socket) do
    actor = socket.assigns.current_scope.actor
    request_id = make_ref()

    socket =
      socket
      |> assign(:search_request_id, request_id)
      |> assign(:searching?, true)
      |> assign(:candidates, [])
      |> assign(:form, to_form(%{"query" => query, "tmdb_id" => ""}, as: :correction))

    {:noreply,
     start_async(socket, {:candidates, request_id}, fn ->
       Identification.search_candidates(actor, query)
     end)}
  end

  def handle_event("choose_candidate", %{"tmdb_id" => id}, socket) do
    case positive_id(id) do
      {:ok, _} ->
        query = socket.assigns.form[:query].value || ""

        {:noreply,
         assign(socket, :form, to_form(%{"query" => query, "tmdb_id" => id}, as: :correction))}

      :error ->
        {:noreply, assign(socket, :feedback, "Candidato inválido.")}
    end
  end

  def handle_event("correct", %{"correction" => %{"tmdb_id" => id}}, socket) do
    case {socket.assigns.selected_file_id, positive_id(id)} do
      {file_id, {:ok, tmdb_id}} when is_integer(file_id) ->
        finish_correction(
          socket,
          Identification.correct(socket.assigns.current_scope.actor, file_id, {:tmdb, tmdb_id})
        )

      _ ->
        {:noreply, assign(socket, :feedback, "Selecciona una película válida.")}
    end
  end

  def handle_event("unidentified", _params, socket) do
    case socket.assigns.selected_file_id do
      nil ->
        {:noreply, assign(socket, :feedback, "Selecciona un archivo.")}

      file_id ->
        finish_correction(
          socket,
          Identification.correct(socket.assigns.current_scope.actor, file_id, :unidentified)
        )
    end
  end

  def handle_event("retry", %{"file_id" => id}, socket) do
    result =
      with {:ok, file_id} <- parse_id(id),
           do: Identification.retry(socket.assigns.current_scope.actor, file_id)

    case result do
      {:ok, _} ->
        {:noreply, socket |> assign(:feedback, "Identificación solicitada de nuevo.") |> load()}

      _ ->
        {:noreply, assign(socket, :feedback, "No se pudo reintentar.")}
    end
  end

  @impl true
  def handle_async({:reviews, request_id}, result, socket) do
    if request_id == socket.assigns.request_id do
      case result do
        {:ok, {:ok, %{items: items, total: total}}} ->
          {:noreply,
           socket
           |> assign(:loading?, false)
           |> assign(:total, total)
           |> stream(:reviews, items, reset: true)}

        _ ->
          {:noreply,
           socket |> assign(:loading?, false) |> assign(:error, "No se pudo cargar la revisión.")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_async({:candidates, request_id}, result, socket) do
    if request_id == socket.assigns.search_request_id do
      case result do
        {:ok, {:ok, candidates}} ->
          {:noreply, socket |> assign(:searching?, false) |> assign(:candidates, candidates)}

        _ ->
          {:noreply,
           socket |> assign(:searching?, false) |> assign(:feedback, "No se pudo buscar en TMDb.")}
      end
    else
      {:noreply, socket}
    end
  end

  defp finish_correction(socket, {:ok, _}) do
    {:noreply,
     socket
     |> assign(:selected_file_id, nil)
     |> assign(:candidates, [])
     |> assign(:feedback, "Corrección guardada.")
     |> load()}
  end

  defp finish_correction(socket, _),
    do: {:noreply, assign(socket, :feedback, "No se pudo guardar la corrección.")}

  defp load(socket) do
    actor = socket.assigns.current_scope.actor
    page = socket.assigns.page
    request_id = make_ref()

    socket
    |> assign(:request_id, request_id)
    |> assign(:loading?, true)
    |> start_async({:reviews, request_id}, fn -> Identification.list_review_items(actor, page) end)
  end

  defp positive_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {value, ""} when value > 0 -> {:ok, value}
      _ -> :error
    end
  end

  defp positive_id(_), do: :error

  defp parse_id(id) do
    case positive_id(id) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, :invalid_choice}
    end
  end

  defp state_label(:pending), do: "Pendiente"
  defp state_label(:failed), do: "Error"
  defp state_label(:unmatched), do: "Sin coincidencia"
  defp state_label(:automatic), do: "Revisar coincidencia"
  defp state_label(_), do: "Revisión"
end
