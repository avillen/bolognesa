defmodule BolognesaWeb.Episode.Show.Reducer.SelectPart do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 2]
  alias Bolognesa.Series.Domain.ReadModels.EpisodeTarget
  alias BolognesaWeb.LiveSupport.PlaybackControl
  alias BolognesaWeb.LiveSupport.PlaybackState

  @spec call(Phoenix.LiveView.Socket.t(), nil | pos_integer() | :invalid) ::
          Phoenix.LiveView.Socket.t()
  def call(socket, requested) do
    PlaybackControl.stop_transcode(socket, :version_selected)
    socket = socket |> PlaybackState.initialize() |> assign(advance_request: nil)
    parts = parts(socket.assigns.detail.versions)
    part = selected_part(socket.assigns.detail.versions, parts, requested)

    if part == :invalid do
      assign(socket, error: gettext("No se encontró la parte del episodio."))
    else
      socket = metadata(socket, part)

      case Enum.find(socket.assigns.part_versions, &(&1.availability == :available)) do
        nil -> socket
        version -> PlaybackControl.select_version(socket, version.id)
      end
    end
  end

  @spec metadata(Phoenix.LiveView.Socket.t(), pos_integer() | nil) :: Phoenix.LiveView.Socket.t()
  def metadata(socket, part) do
    detail = socket.assigns.detail
    parts = parts(detail.versions)
    index = Enum.find_index(parts, &(&1 == part))

    previous =
      if index && index > 0,
        do: target(detail, Enum.at(parts, index - 1)),
        else: detail.previous_entry

    next =
      if index && index < length(parts) - 1,
        do: target(detail, Enum.at(parts, index + 1)),
        else: detail.next_entry

    assign(socket,
      active_part: part,
      parts: parts,
      part_versions: Enum.filter(detail.versions, &(&1.part_number == part)),
      playback_versions:
        Enum.filter(detail.versions, &(&1.part_number == part or is_nil(&1.part_number))),
      previous_target: previous,
      next_target: next,
      error: nil
    )
  end

  defp parts(versions),
    do:
      versions
      |> Enum.map(& &1.part_number)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

  defp selected_part(_, _, :invalid), do: :invalid

  defp selected_part(versions, parts, nil) do
    if Enum.any?(versions, &(is_nil(&1.part_number) and &1.availability == :available)),
      do: nil,
      else: List.first(parts)
  end

  defp selected_part(_, parts, requested),
    do: if(requested in parts, do: requested, else: :invalid)

  defp target(detail, part),
    do: %EpisodeTarget{id: detail.episode.id, season_id: detail.season.id, part_number: part}
end
