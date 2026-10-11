defmodule BolognesaWeb.Series.Review.Reducer.LoadSeason do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2, to_form: 2]
  import Phoenix.LiveView, only: [stream: 4]
  alias Bolognesa.Identification
  alias BolognesaWeb.Series.Review.AsyncRequest
  @spec call(Phoenix.LiveView.Socket.t(), non_neg_integer()) :: Phoenix.LiveView.Socket.t()
  def call(%{assigns: %{saving?: true}} = socket, _), do: socket

  def call(%{assigns: %{series_id: nil}} = socket, _),
    do: assign(socket, feedback: "Selecciona una serie.")

  def call(socket, number) do
    actor = socket.assigns.current_scope.actor
    id = socket.assigns.series_id

    socket
    |> assign(
      season_loading?: true,
      season_number: nil,
      episode_numbers: [],
      feedback: nil,
      season_form: to_form(%{"number" => number}, as: :season)
    )
    |> stream(:episodes, [], reset: true)
    |> AsyncRequest.start(:season, fn -> Identification.series_season(actor, id, number) end)
  end
end
