defmodule BolognesaWeb.Series.Review.Reducer.ApplyResult do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [stream: 4]
  alias BolognesaWeb.Series.Review.Reducer.Load
  @type kind :: :reviews | :candidates | :season | :correction
  @spec call(Phoenix.LiveView.Socket.t(), kind(), reference(), {:ok, term()} | {:exit, term()}) ::
          Phoenix.LiveView.Socket.t()
  def call(socket, kind, ref, result) do
    if Map.get(socket.assigns.requests, kind) == ref,
      do:
        apply_result(
          assign(socket, requests: Map.delete(socket.assigns.requests, kind)),
          kind,
          result
        ),
      else: socket
  end

  defp apply_result(socket, :reviews, {:ok, {:ok, {page, item}}}) do
    socket
    |> assign(loading?: false, error: nil, total: page.total, selected_item: item)
    |> stream(:reviews, page.items, reset: true)
  end

  defp apply_result(socket, :reviews, _),
    do:
      assign(socket,
        loading?: false,
        error:
          gettext("No se pudo cargar la revisión. Comprueba el archivo y vuelve a intentarlo."),
        selected_item: nil
      )

  defp apply_result(socket, :candidates, {:ok, {:ok, items}}) do
    socket
    |> assign(
      searching?: false,
      candidate_titles: Map.new(items, &{&1.provider_id, &1.title}),
      feedback: if(items == [], do: gettext("No se encontraron series."), else: nil)
    )
    |> stream(:candidates, items, reset: true)
  end

  defp apply_result(socket, :candidates, _),
    do:
      assign(socket,
        searching?: false,
        feedback: gettext("No se pudo buscar en TMDb. Vuelve a intentarlo.")
      )

  defp apply_result(socket, :season, {:ok, {:ok, season}}) do
    episodes = Enum.map(season.episodes, &Map.put(&1, :id, &1.number))

    socket
    |> assign(
      season_loading?: false,
      season_number: season.number,
      episode_numbers: Enum.map(episodes, & &1.number),
      feedback: if(episodes == [], do: gettext("La temporada no contiene episodios."), else: nil)
    )
    |> stream(:episodes, episodes, reset: true)
  end

  defp apply_result(socket, :season, _),
    do:
      assign(socket,
        season_loading?: false,
        feedback: gettext("No se pudo cargar la temporada. Vuelve a intentarlo.")
      )

  defp apply_result(socket, :correction, {:ok, {:ok, _}}) do
    socket
    |> assign(saving?: false, feedback: gettext("Identificación guardada."))
    |> Load.call(socket.assigns.page, socket.assigns.selected_file_id)
  end

  defp apply_result(socket, :correction, {:ok, {:error, :source_changed}}),
    do:
      assign(socket,
        saving?: false,
        feedback: gettext("El archivo ha cambiado. Recarga antes de corregirlo.")
      )

  defp apply_result(socket, :correction, _),
    do:
      assign(socket,
        saving?: false,
        feedback: gettext("No se pudo guardar la selección completa. Vuelve a intentarlo.")
      )
end
