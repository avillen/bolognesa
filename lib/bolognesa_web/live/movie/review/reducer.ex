defmodule BolognesaWeb.Movie.Review.Reducer do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [stream: 4, start_async: 3]
  alias Bolognesa.Identification

  def select_file(socket, file_id) do
    socket
    |> assign(:selected_file_id, file_id)
    |> assign(:candidates, [])
    |> assign(:search_request_id, make_ref())
    |> assign(:searching?, false)
    |> assign(:saving?, false)
    |> assign(:correction_request_id, make_ref())
    |> assign(:form, to_form(%{"query" => "", "tmdb_id" => ""}, as: :correction))
    |> assign(:feedback, nil)
  end

  def load(socket) do
    actor = socket.assigns.current_scope.actor
    page = socket.assigns.page
    request_id = make_ref()

    socket
    |> assign(:request_id, request_id)
    |> assign(:loading?, true)
    |> start_async({:reviews, request_id}, fn -> Identification.list_review_items(actor, page) end)
  end

  def begin_correction(socket, file_id, choice) do
    actor = socket.assigns.current_scope.actor
    request_id = make_ref()

    socket
    |> assign(:correction_request_id, request_id)
    |> assign(:saving?, true)
    |> assign(:feedback, nil)
    |> start_async({:correction, request_id}, fn ->
      Identification.correct(actor, file_id, choice)
    end)
  end

  def reviews_result(socket, request_id, result) do
    if request_id == socket.assigns.request_id do
      case result do
        {:ok, {:ok, %{items: items, total: total}}} ->
          socket
          |> assign(:loading?, false)
          |> assign(:total, total)
          |> stream(:reviews, items, reset: true)

        _ ->
          socket |> assign(:loading?, false) |> assign(:error, "No se pudo cargar la revisión.")
      end
    else
      socket
    end
  end

  def candidates_result(socket, request_id, result) do
    if request_id == socket.assigns.search_request_id do
      case result do
        {:ok, {:ok, candidates}} ->
          socket |> assign(:searching?, false) |> assign(:candidates, candidates)

        {:ok, {:error, :not_configured}} ->
          socket
          |> assign(:searching?, false)
          |> assign(:feedback, "TMDb sin configurar. Añade TMDB_READ_TOKEN al servidor.")

        _ ->
          socket |> assign(:searching?, false) |> assign(:feedback, "No se pudo buscar en TMDb.")
      end
    else
      socket
    end
  end

  def correction_result(socket, request_id, result) do
    if request_id == socket.assigns.correction_request_id do
      socket = assign(socket, :saving?, false)

      case result do
        {:ok, {:ok, _}} ->
          socket
          |> select_file(nil)
          |> assign(:feedback, "Corrección guardada.")
          |> load()

        _ ->
          assign(socket, :feedback, "No se pudo guardar la corrección.")
      end
    else
      socket
    end
  end
end
