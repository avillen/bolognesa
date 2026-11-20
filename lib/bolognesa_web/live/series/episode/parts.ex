defmodule BolognesaWeb.Series.Episode.Parts do
  @moduledoc "Screen-local helper that assigns the active episode part and its navigation."
  import Phoenix.Component, only: [assign: 2]
  alias Bolognesa.Series.Domain.ReadModels.EntryStatus
  alias Bolognesa.Series.Domain.ValueObjects.Entry

  @doc "Assigns the part, its versions, and the previous and next entries."
  @spec assign_part(Phoenix.LiveView.Socket.t(), pos_integer() | nil) ::
          Phoenix.LiveView.Socket.t()
  def assign_part(socket, part) do
    detail = socket.assigns.detail
    entry = %Entry{episode_id: detail.episode.id, part_number: part}
    {previous, next} = EntryStatus.adjacent(detail.entries, entry)

    assign(socket,
      active_part: part,
      parts: numbers(detail.versions),
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
end
