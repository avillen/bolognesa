defmodule BolognesaWeb.Series.Review.Reducer.BeginCorrection do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2, to_form: 2]
  alias BolognesaWeb.Series.Review.Forms.Selection
  alias BolognesaWeb.Series.Review.Reducer.Save
  @spec call(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def call(%{assigns: %{saving?: true}} = socket, _), do: socket

  def call(socket, params) do
    changeset = Selection.changeset(params)

    socket =
      assign(socket, selection_form: to_form(%{changeset | action: :validate}, as: :selection))

    with {:ok, selection} <- Ecto.Changeset.apply_action(changeset, :insert),
         :ok <- ready(socket, selection.episode_numbers) do
      Save.call(
        socket,
        {:tmdb, socket.assigns.series_id, socket.assigns.season_number, selection.episode_numbers}
      )
    else
      _ ->
        assign(socket,
          feedback: "Selecciona una serie, una temporada y al menos un episodio válido."
        )
    end
  end

  defp ready(socket, numbers) do
    if socket.assigns.selected_item && is_integer(socket.assigns.series_id) &&
         is_integer(socket.assigns.season_number) &&
         Enum.all?(numbers, &(&1 in socket.assigns.episode_numbers)), do: :ok, else: :error
  end
end
