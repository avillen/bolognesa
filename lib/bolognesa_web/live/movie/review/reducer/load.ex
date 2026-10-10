defmodule BolognesaWeb.Movie.Review.Reducer.Load do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 3]
  alias Bolognesa.Identification

  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(socket) do
    actor = socket.assigns.current_scope.actor
    page = socket.assigns.page
    request_id = make_ref()

    socket
    |> assign(:request_id, request_id)
    |> assign(:loading?, true)
    |> start_async({:reviews, request_id}, fn -> Identification.list_review_items(actor, page) end)
  end
end
