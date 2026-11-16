defmodule BolognesaWeb.Series.Episode.Parts do
  @moduledoc "Screen-local helper that assigns the active episode part and its navigation."
  import Phoenix.Component, only: [assign: 2]
  alias Bolognesa.Series.Domain.ReadModels.EpisodeTarget

  @doc "Assigns the part, its versions, and the previous and next targets."
  @spec assign_part(Phoenix.LiveView.Socket.t(), pos_integer() | nil) ::
          Phoenix.LiveView.Socket.t()
  def assign_part(socket, part) do
    detail = socket.assigns.detail
    parts = numbers(detail.versions)
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

  @doc "Returns the sorted part numbers of the episode versions."
  @spec numbers([map()]) :: [pos_integer()]
  def numbers(versions),
    do:
      versions
      |> Enum.map(& &1.part_number)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

  defp target(detail, part),
    do: %EpisodeTarget{id: detail.episode.id, season_id: detail.season.id, part_number: part}
end
