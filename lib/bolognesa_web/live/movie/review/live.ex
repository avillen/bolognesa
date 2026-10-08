defmodule BolognesaWeb.Movie.Review.Live do
  use BolognesaWeb, :live_view
  alias Bolognesa.Identification
  alias BolognesaWeb.Movie.Review.Reducer

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
      |> assign(:saving?, false)
      |> assign(:request_id, nil)
      |> assign(:search_request_id, nil)
      |> assign(:correction_request_id, nil)
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

    selected_file_id =
      case positive_id(Map.get(params, "file_id")) do
        {:ok, id} -> id
        :error -> socket.assigns.selected_file_id
      end

    socket =
      if selected_file_id != socket.assigns.selected_file_id,
        do: Reducer.select_file(socket, selected_file_id),
        else: socket

    {:noreply, socket |> assign(:page, page) |> Reducer.load()}
  end

  @impl true
  def handle_event("select", %{"file_id" => id}, socket) do
    case positive_id(id) do
      {:ok, file_id} ->
        {:noreply, Reducer.select_file(socket, file_id)}

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
        {:noreply, Reducer.begin_correction(socket, file_id, {:tmdb, tmdb_id})}

      _ ->
        {:noreply, assign(socket, :feedback, "Selecciona una película válida.")}
    end
  end

  def handle_event("unidentified", _params, socket) do
    case socket.assigns.selected_file_id do
      nil ->
        {:noreply, assign(socket, :feedback, "Selecciona un archivo.")}

      file_id ->
        {:noreply, Reducer.begin_correction(socket, file_id, :unidentified)}
    end
  end

  def handle_event("retry", %{"file_id" => id}, socket) do
    result =
      with {:ok, file_id} <- parse_id(id),
           do: Identification.retry(socket.assigns.current_scope.actor, file_id)

    case result do
      {:ok, _} ->
        {:noreply,
         socket |> assign(:feedback, "Identificación solicitada de nuevo.") |> Reducer.load()}

      _ ->
        {:noreply, assign(socket, :feedback, "No se pudo reintentar.")}
    end
  end

  @impl true
  def handle_async({:reviews, request_id}, result, socket),
    do: {:noreply, Reducer.reviews_result(socket, request_id, result)}

  def handle_async({:candidates, request_id}, result, socket),
    do: {:noreply, Reducer.candidates_result(socket, request_id, result)}

  def handle_async({:correction, request_id}, result, socket),
    do: {:noreply, Reducer.correction_result(socket, request_id, result)}

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
  defp state_label(:manual_unidentified), do: "Sin identificar manualmente"
  defp state_label(:automatic), do: "Revisar coincidencia"
  defp state_label(_), do: "Revisión"

  defp failure_label("not_configured"), do: "TMDb sin configurar"
  defp failure_label("rate_limited"), do: "TMDb limitó las solicitudes"
  defp failure_label("provider_unavailable"), do: "TMDb no disponible"
  defp failure_label("unauthorized"), do: "Token de TMDb rechazado"
  defp failure_label("unusable_name"), do: "Nombre de archivo no interpretable"
  defp failure_label("attempts_exhausted"), do: "Se agotaron los reintentos"
  defp failure_label(_), do: "No se pudo identificar"
end
