defmodule BolognesaWeb.Movie.Review.Reducer.Initialize do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [stream_configure: 3, stream: 3]

  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(socket) do
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
  end
end
