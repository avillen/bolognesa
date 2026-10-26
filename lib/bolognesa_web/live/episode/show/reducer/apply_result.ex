defmodule BolognesaWeb.Episode.Show.Reducer.ApplyResult do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 3]
  alias BolognesaWeb.Episode.Show.Reducer.SelectPart

  @spec call(Phoenix.LiveView.Socket.t(), reference(), term()) :: Phoenix.LiveView.Socket.t()
  def call(socket, request_id, result) do
    if socket.assigns.request_id == request_id,
      do: apply_result(socket, result),
      else: socket
  end

  defp apply_result(socket, {:ok, {:ok, detail}}) do
    socket
    |> assign(:loading?, false)
    |> assign(:detail, detail)
    |> assign(
      :multi_episode?,
      Enum.any?(detail.versions, &(length(&1.episode_numbers) > 1))
    )
    |> SelectPart.call(socket.assigns.requested_part)
  end

  defp apply_result(socket, {:ok, {:error, :too_many_versions}}),
    do:
      socket
      |> assign(:loading?, false)
      |> assign(:error, gettext("Esta ficha supera el límite de 100 elementos."))

  defp apply_result(socket, _),
    do:
      socket |> assign(:loading?, false) |> assign(:error, gettext("No se encontró el episodio."))
end
