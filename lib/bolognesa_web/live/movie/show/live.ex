defmodule BolognesaWeb.Movie.Show.Live do
  use BolognesaWeb, :live_view
  alias BolognesaWeb.Movie.Show.Reducer

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_scope.actor
    {:ok, Reducer.load(socket, actor, parse_id(id))}
  end

  @impl true
  def handle_async({:movie, request_id}, result, socket) do
    {:noreply, Reducer.result(socket, request_id, result)}
  end

  defp parse_id(id) do
    case Integer.parse(id) do
      {value, ""} when value > 0 -> value
      _ -> 0
    end
  end
end
