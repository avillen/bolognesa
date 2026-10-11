defmodule BolognesaWeb.Series.Review.Live do
  @moduledoc false
  use BolognesaWeb, :live_view
  alias Bolognesa.Identification
  alias BolognesaWeb.Series.Review.Reducer
  @impl true
  def mount(_, _, socket), do: {:ok, Reducer.Initialize.call(socket)}
  @impl true
  def handle_params(_, _, %{assigns: %{saving?: true}} = socket), do: {:noreply, socket}

  def handle_params(params, _, socket) do
    page = min(integer(params["page"], 1, 1), 100_000)
    file_id = integer(params["file_id"], 1, nil)

    socket =
      if file_id != socket.assigns.selected_file_id,
        do: socket |> Reducer.ResetSelection.call() |> assign(:selected_item, nil),
        else: socket

    {:noreply, Reducer.Load.call(socket, page, file_id)}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket),
    do: {:noreply, Reducer.Search.call(socket, query)}

  def handle_event("choose", %{"id" => id}, socket),
    do: {:noreply, Reducer.ChooseSeries.call(socket, integer(id, 1, nil))}

  def handle_event("season", %{"season" => %{"number" => number}}, socket) do
    case integer(number, 0, nil) do
      nil -> {:noreply, assign(socket, :feedback, "Temporada inválida.")}
      value -> {:noreply, Reducer.LoadSeason.call(socket, value)}
    end
  end

  def handle_event("correct", params, socket),
    do: {:noreply, Reducer.BeginCorrection.call(socket, Map.get(params, "selection", %{}))}

  def handle_event("unidentified", _, socket),
    do: {:noreply, Reducer.Save.call(socket, :unidentified)}

  def handle_event("retry", _, %{assigns: %{saving?: true}} = socket), do: {:noreply, socket}

  def handle_event("retry", %{"file_id" => id}, socket) do
    result =
      case integer(id, 1, nil) do
        nil -> {:error, :invalid_choice}
        file_id -> Identification.retry(socket.assigns.current_scope.actor, file_id)
      end

    socket =
      case result do
        {:ok, _} ->
          socket
          |> assign(:feedback, "Identificación solicitada de nuevo.")
          |> Reducer.Load.call(socket.assigns.page, socket.assigns.selected_file_id)

        _ ->
          assign(socket, :feedback, "No se pudo reintentar.")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_async({kind, ref}, result, socket),
    do: {:noreply, Reducer.ApplyResult.call(socket, kind, ref, result)}

  defp integer(value, min, default) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id >= min and id <= 100_000_000 -> id
      _ -> default
    end
  end

  defp integer(_, _, default), do: default
  defp state_label(:pending), do: "Pendiente"
  defp state_label(:failed), do: "Error"
  defp state_label(:unmatched), do: "Sin coincidencia"
  defp state_label(:manual_unidentified), do: "Sin identificar manualmente"
  defp state_label(_), do: "Revisar identificación"
  defp failure_label("incomplete_episodes"), do: "TMDb no contiene todos los episodios indicados"
  defp failure_label("unusable_name"), do: "Nombre de archivo no interpretable"
  defp failure_label("not_configured"), do: "TMDb sin configurar"
  defp failure_label("rate_limited"), do: "TMDb limitó las solicitudes"
  defp failure_label(_), do: "La identificación necesita revisión"
end
