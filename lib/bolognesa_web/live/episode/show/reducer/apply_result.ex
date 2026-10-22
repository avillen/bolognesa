defmodule BolognesaWeb.Episode.Show.Reducer.ApplyResult do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 3]
  alias BolognesaWeb.LiveSupport.PlaybackControl

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
    |> select_first_available(detail.versions)
  end

  defp apply_result(socket, {:ok, {:error, :too_many_versions}}),
    do:
      socket
      |> assign(:loading?, false)
      |> assign(:error, gettext("Esta ficha supera el límite de 100 elementos."))

  defp apply_result(socket, _),
    do:
      socket |> assign(:loading?, false) |> assign(:error, gettext("No se encontró el episodio."))

  defp select_first_available(socket, versions) do
    case Enum.find(versions, &(&1.availability == :available)) do
      nil -> socket
      version -> PlaybackControl.select_version(socket, version.id)
    end
  end
end
