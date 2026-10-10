defmodule BolognesaWeb.Movie.Index.Reducer.Initialize do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [stream: 3]

  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(socket) do
    socket
    |> assign(:query, "")
    |> assign(:page, 1)
    |> assign(:total, 0)
    |> assign(:loading?, true)
    |> assign(:error, nil)
    |> assign(:request_id, nil)
    |> assign(:form, to_form(%{"query" => ""}, as: :search))
    |> stream(:movies, [])
  end
end
