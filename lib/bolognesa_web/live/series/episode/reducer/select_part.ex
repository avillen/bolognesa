defmodule BolognesaWeb.Series.Episode.Reducer.SelectPart do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 2]
  alias BolognesaWeb.LiveSupport.PlaybackControl
  alias BolognesaWeb.LiveSupport.PlaybackState
  alias BolognesaWeb.Series.Episode.Parts

  @spec call(Phoenix.LiveView.Socket.t(), nil | pos_integer() | :invalid) ::
          Phoenix.LiveView.Socket.t()
  def call(socket, requested) do
    PlaybackControl.stop_transcode(socket, :version_selected)
    socket = socket |> PlaybackState.initialize() |> assign(advance_request: nil)
    parts = Parts.numbers(socket.assigns.detail.versions)
    part = selected_part(socket.assigns.detail.versions, parts, requested)

    if part == :invalid do
      assign(socket, error: gettext("No se encontró la parte del episodio."))
    else
      socket = Parts.assign_part(socket, part)

      case Enum.find(socket.assigns.part_versions, &(&1.availability == :available)) do
        nil -> socket
        version -> PlaybackControl.select_version(socket, version.id)
      end
    end
  end

  defp selected_part(_, _, :invalid), do: :invalid

  defp selected_part(versions, parts, nil) do
    if Enum.any?(versions, &(is_nil(&1.part_number) and &1.availability == :available)),
      do: nil,
      else: List.first(parts)
  end

  defp selected_part(_, parts, requested),
    do: if(requested in parts, do: requested, else: :invalid)
end
