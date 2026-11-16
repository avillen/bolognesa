defmodule BolognesaWeb.Series.Review.Live do
  @moduledoc false
  use BolognesaWeb, :live_view
  alias Bolognesa.Series
  alias BolognesaWeb.Params
  alias BolognesaWeb.Series.Review.Components.ReviewItem
  alias BolognesaWeb.Series.Review.Reducer.ApplyCandidatesResult
  alias BolognesaWeb.Series.Review.Reducer.ApplyCorrectionResultCoordinator
  alias BolognesaWeb.Series.Review.Reducer.ApplyReviewsResult
  alias BolognesaWeb.Series.Review.Reducer.ApplySeasonResult
  alias BolognesaWeb.Series.Review.Reducer.BeginCorrectionCoordinator
  alias BolognesaWeb.Series.Review.Reducer.ChooseSeriesCoordinator
  alias BolognesaWeb.Series.Review.Reducer.Initialize
  alias BolognesaWeb.Series.Review.Reducer.Load
  alias BolognesaWeb.Series.Review.Reducer.LoadSeason
  alias BolognesaWeb.Series.Review.Reducer.ResetSelection
  alias BolognesaWeb.Series.Review.Reducer.Save
  alias BolognesaWeb.Series.Review.Reducer.Search
  @impl true
  def mount(_, _, socket), do: {:ok, Initialize.call(socket)}
  @impl true
  def handle_params(_, _, %{assigns: %{saving?: true}} = socket), do: {:noreply, socket}

  def handle_params(params, _, socket) do
    page = min(integer(params["page"], 1, 1), 100_000)
    file_id = integer(params["file_id"], 1, nil)

    socket =
      if file_id != socket.assigns.selected_file_id,
        do: socket |> ResetSelection.call() |> assign(:selected_item, nil),
        else: socket

    {:noreply, Load.call(socket, page, file_id)}
  end

  @impl true
  def handle_event("search", _params, %{assigns: %{saving?: true}} = socket),
    do: {:noreply, socket}

  def handle_event("search", %{"search" => %{"query" => query}}, socket),
    do: {:noreply, socket |> ResetSelection.call() |> Search.call(query)}

  def handle_event("choose", %{"id" => id}, socket),
    do: {:noreply, ChooseSeriesCoordinator.call(socket, integer(id, 1, nil))}

  def handle_event("season", %{"season" => %{"number" => number}}, socket) do
    case integer(number, 0, nil) do
      nil -> {:noreply, assign(socket, :feedback, gettext("Temporada inválida."))}
      value -> {:noreply, LoadSeason.call(socket, value)}
    end
  end

  def handle_event("correct", params, socket),
    do: {:noreply, BeginCorrectionCoordinator.call(socket, Map.get(params, "selection", %{}))}

  def handle_event("unidentified", _, socket),
    do: {:noreply, Save.call(socket, :unidentified)}

  def handle_event("retry", _, %{assigns: %{saving?: true}} = socket), do: {:noreply, socket}

  def handle_event("retry", %{"file_id" => id}, socket) do
    result =
      case integer(id, 1, nil) do
        nil -> {:error, :invalid_choice}
        file_id -> Series.retry(socket.assigns.current_scope.actor, file_id)
      end

    socket =
      case result do
        {:ok, _} ->
          socket
          |> assign(:feedback, gettext("Identificación solicitada de nuevo."))
          |> Load.call(socket.assigns.page, socket.assigns.selected_file_id)

        _ ->
          assign(socket, :feedback, gettext("No se pudo reintentar."))
      end

    {:noreply, socket}
  end

  @impl true
  def handle_async({:reviews, ref}, result, socket),
    do: {:noreply, ApplyReviewsResult.call(socket, ref, result)}

  def handle_async({:candidates, ref}, result, socket),
    do: {:noreply, ApplyCandidatesResult.call(socket, ref, result)}

  def handle_async({:season, ref}, result, socket),
    do: {:noreply, ApplySeasonResult.call(socket, ref, result)}

  def handle_async({:correction, ref}, result, socket),
    do: {:noreply, ApplyCorrectionResultCoordinator.call(socket, ref, result)}

  defp integer(value, min, default), do: Params.integer(value, min..100_000_000) || default
end
