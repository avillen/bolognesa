defmodule BolognesaWeb.Episode.Show.Reducer.ApplyResult do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 3]
  alias BolognesaWeb.Episode.Show.Reducer.SelectPart
  alias BolognesaWeb.LiveSupport.PlaybackControl
  alias BolognesaWeb.LiveSupport.PlaybackState

  @spec call(Phoenix.LiveView.Socket.t(), reference(), term()) :: Phoenix.LiveView.Socket.t()
  def call(socket, request_id, result) do
    if socket.assigns.request_id == request_id,
      do: apply_result(socket, result),
      else: socket
  end

  defp apply_result(socket, {:ok, {:ok, detail}}) do
    socket
    |> assign(:loading?, false)
    |> assign(:content_ref, {:episode, detail.episode.id})
    |> assign(:detail, detail)
    |> assign(
      :multi_episode?,
      Enum.any?(detail.versions, &(length(&1.episode_numbers) > 1))
    )
    |> SelectPart.call(socket.assigns.requested_part)
  end

  defp apply_result(socket, {:ok, {:error, :too_many_versions}}),
    do: failed(socket, gettext("Esta ficha supera el límite de 100 elementos."))

  defp apply_result(socket, _), do: failed(socket, gettext("No se encontró el episodio."))

  defp failed(socket, message) do
    PlaybackControl.stop_transcode(socket, :version_selected)

    socket
    |> PlaybackState.initialize()
    |> assign(:detail, nil)
    |> assign(:playback_versions, [])
    |> assign(:loading?, false)
    |> assign(:error, message)
  end
end
