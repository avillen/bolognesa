defmodule BolognesaWeb.Series.Review.Reducer.ApplyCandidatesResult do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [stream: 4]
  alias BolognesaWeb.Series.Review.AsyncRequest

  @spec call(Phoenix.LiveView.Socket.t(), reference(), {:ok, term()} | {:exit, term()}) ::
          Phoenix.LiveView.Socket.t()
  def call(socket, ref, result) do
    case AsyncRequest.complete(socket, :candidates, ref) do
      {:ok, socket} -> apply_result(socket, result)
      :stale -> socket
    end
  end

  defp apply_result(socket, {:ok, {:ok, items}}) do
    socket
    |> assign(
      searching?: false,
      candidate_titles: Map.new(items, &{&1.provider_id, &1.title}),
      feedback: if(items == [], do: gettext("No se encontraron series."), else: nil)
    )
    |> stream(:candidates, items, reset: true)
  end

  defp apply_result(socket, _),
    do:
      assign(socket,
        searching?: false,
        feedback: gettext("No se pudo buscar en TMDb. Vuelve a intentarlo.")
      )
end
