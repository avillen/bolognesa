defmodule BolognesaWeb.Series.Review.Reducer.Initialize do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2, to_form: 2]
  import Phoenix.LiveView, only: [stream: 3, stream_configure: 3]
  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(socket) do
    socket
    |> assign(
      page: 1,
      total: 0,
      loading?: true,
      error: nil,
      feedback: nil,
      selected_file_id: nil,
      selected_item: nil,
      candidate_titles: %{},
      series_id: nil,
      series_title: nil,
      season_number: nil,
      episode_numbers: [],
      searching?: false,
      season_loading?: false,
      saving?: false,
      requests: %{},
      search_form: to_form(%{"query" => ""}, as: :search),
      season_form: to_form(%{"number" => "1"}, as: :season),
      selection_form: to_form(%{"episode_numbers" => []}, as: :selection)
    )
    |> stream_configure(:reviews, dom_id: &"series-review-#{&1.file_id}")
    |> stream_configure(:candidates, dom_id: &"series-candidate-#{&1.provider_id}")
    |> stream_configure(:episodes, dom_id: &"select-episode-#{&1.number}")
    |> stream(:reviews, [])
    |> stream(:candidates, [])
    |> stream(:episodes, [])
  end
end
