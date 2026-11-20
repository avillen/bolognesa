defmodule Bolognesa.Series.Domain.ReadModels.EntryStatus do
  @moduledoc "A known entry in series order, with availability and the account's latest watched date, if any."
  alias Bolognesa.Series.Domain.ReadModels.Episode
  alias Bolognesa.Series.Domain.ReadModels.Series
  alias Bolognesa.Series.Domain.ValueObjects.Entry

  @type t :: %__MODULE__{
          series_id: Series.id(),
          season_id: pos_integer(),
          season_number: non_neg_integer(),
          number: pos_integer(),
          episode_id: Episode.id(),
          part_number: Entry.part_number(),
          available?: boolean(),
          last_watched_at: DateTime.t() | nil
        }
  @enforce_keys [:season_id, :season_number, :number, :episode_id, :part_number, :available?]
  defstruct [
    :series_id,
    :season_id,
    :season_number,
    :number,
    :episode_id,
    :part_number,
    :available?,
    :last_watched_at
  ]

  @spec entry(t()) :: Entry.t()
  def entry(status),
    do: %Entry{episode_id: status.episode_id, part_number: status.part_number}

  @doc """
  The entries before and after `entry` in the given ordered entries, including unavailable ones.

  An entry that is not listed, such as a whole-episode version of a split episode, navigates
  around all entries of its episode.
  """
  @spec adjacent([t()], Entry.t()) :: {t() | nil, t() | nil}
  def adjacent(entries, %Entry{episode_id: id} = entry) do
    case Enum.find_index(entries, &(entry(&1) == entry)) do
      nil ->
        {before, rest} = Enum.split_while(entries, &(&1.episode_id != id))
        {List.last(before), Enum.find(rest, &(&1.episode_id != id))}

      0 ->
        {nil, Enum.at(entries, 1)}

      index ->
        {Enum.at(entries, index - 1), Enum.at(entries, index + 1)}
    end
  end
end
