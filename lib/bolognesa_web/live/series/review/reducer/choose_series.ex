defmodule BolognesaWeb.Series.Review.Reducer.ChooseSeries do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 2]
  alias BolognesaWeb.Series.Review.Reducer.ResetSelection
  @spec call(Phoenix.LiveView.Socket.t(), pos_integer()) :: Phoenix.LiveView.Socket.t()
  def call(%{assigns: %{saving?: true}} = socket, _), do: socket

  def call(socket, id) do
    case Map.fetch(socket.assigns.candidate_titles, id) do
      {:ok, title} ->
        socket |> ResetSelection.call() |> assign(series_id: id, series_title: title)

      :error ->
        assign(socket, feedback: gettext("Selecciona una serie de los resultados."))
    end
  end
end
