defmodule BolognesaWeb.Series.Index.Reducer.Load do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [cancel_async: 2, start_async: 3]
  alias Bolognesa.Series

  @spec call(Phoenix.LiveView.Socket.t(), String.t(), pos_integer()) ::
          Phoenix.LiveView.Socket.t()
  def call(socket, query, page) do
    actor = socket.assigns.current_scope.actor
    library_id = socket.assigns.active_library_id
    request_id = make_ref()

    # The new request discards the previous result, so stop its read instead of letting it run.
    socket
    |> cancel_async({:series, socket.assigns.request_id})
    |> assign(:query, query)
    |> assign(:page, page)
    |> assign(:loading?, true)
    |> assign(:error, nil)
    |> assign(:request_id, request_id)
    |> assign(:form, to_form(%{"query" => query}, as: :search))
    |> start_async({:series, request_id}, fn ->
      Series.search_series(actor, query, page, library_id)
    end)
  end
end
