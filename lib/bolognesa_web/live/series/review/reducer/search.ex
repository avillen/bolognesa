defmodule BolognesaWeb.Series.Review.Reducer.Search do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2, to_form: 2]
  import Phoenix.LiveView, only: [stream: 4]
  alias Bolognesa.Series
  alias BolognesaWeb.Series.Review.AsyncRequest
  alias BolognesaWeb.Series.Review.Reducer.ResetSelection
  @spec call(Phoenix.LiveView.Socket.t(), binary()) :: Phoenix.LiveView.Socket.t()
  def call(%{assigns: %{saving?: true}} = socket, _), do: socket

  def call(socket, query) do
    actor = socket.assigns.current_scope.actor

    socket
    |> ResetSelection.call()
    |> assign(
      searching?: true,
      candidate_titles: %{},
      search_form: to_form(%{"query" => query}, as: :search)
    )
    |> stream(:candidates, [], reset: true)
    |> AsyncRequest.start(:candidates, fn ->
      Series.search_candidates(actor, query)
    end)
  end
end
