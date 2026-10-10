defmodule BolognesaWeb.Movie.Review.Reducer.SelectFile do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3, to_form: 2]

  @spec call(Phoenix.LiveView.Socket.t(), pos_integer() | nil) :: Phoenix.LiveView.Socket.t()
  def call(socket, file_id) do
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
end
