defmodule BolognesaWeb.Series.Review.Reducer.ResetSelection do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2, to_form: 2]
  import Phoenix.LiveView, only: [stream: 4]
  alias BolognesaWeb.Series.Review.AsyncRequest
  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(socket) do
    socket = socket |> AsyncRequest.cancel(:season) |> AsyncRequest.cancel(:candidates)
    requests = socket.assigns.requests |> Map.delete(:season) |> Map.delete(:candidates)

    socket
    |> assign(
      requests: requests,
      series_id: nil,
      series_title: nil,
      season_number: nil,
      episode_numbers: [],
      season_loading?: false,
      searching?: false,
      feedback: nil,
      selection_form: to_form(%{"episode_numbers" => []}, as: :selection)
    )
    |> stream(:episodes, [], reset: true)
  end
end
