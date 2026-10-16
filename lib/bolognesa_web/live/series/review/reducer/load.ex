defmodule BolognesaWeb.Series.Review.Reducer.Load do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [start_async: 3]
  alias Bolognesa.Series

  @spec call(Phoenix.LiveView.Socket.t(), pos_integer(), pos_integer() | nil) ::
          Phoenix.LiveView.Socket.t()
  def call(socket, page, file_id) do
    actor = socket.assigns.current_scope.actor
    request = make_ref()
    requests = Map.put(socket.assigns.requests, :reviews, request)

    socket
    |> assign(
      page: page,
      selected_file_id: file_id,
      loading?: true,
      error: nil,
      requests: requests
    )
    |> start_async({:reviews, request}, fn ->
      with {:ok, rows} <- Series.list_review_items(actor, page),
           {:ok, item} <- selected(actor, file_id) do
        {:ok, {rows, item}}
      end
    end)
  end

  defp selected(_, nil), do: {:ok, nil}
  defp selected(actor, id), do: Series.get_review_item(actor, id)
end
