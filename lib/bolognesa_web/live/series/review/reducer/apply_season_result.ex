defmodule BolognesaWeb.Series.Review.Reducer.ApplySeasonResult do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [stream: 4]
  alias BolognesaWeb.Series.Review.AsyncRequest

  @spec call(Phoenix.LiveView.Socket.t(), reference(), {:ok, term()} | {:exit, term()}) ::
          Phoenix.LiveView.Socket.t()
  def call(socket, ref, result) do
    case AsyncRequest.complete(socket, :season, ref) do
      {:ok, socket} -> apply_result(socket, result)
      :stale -> socket
    end
  end

  defp apply_result(socket, {:ok, {:ok, season}}) do
    episodes = Enum.map(season.episodes, &Map.put(&1, :id, &1.number))

    socket
    |> assign(
      season_loading?: false,
      season_number: season.number,
      episode_numbers: Enum.map(episodes, & &1.number),
      feedback: if(episodes == [], do: gettext("La temporada no contiene episodios."), else: nil)
    )
    |> stream(:episodes, episodes, reset: true)
  end

  defp apply_result(socket, _),
    do:
      assign(socket,
        season_loading?: false,
        feedback: gettext("No se pudo cargar la temporada. Vuelve a intentarlo.")
      )
end
