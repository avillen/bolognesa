defmodule Bolognesa.Series.Domain.ReadModels.SeasonEntryStatus do
  @moduledoc "A known season entry in series order, with availability and the account's latest watched date, if any."
  alias Bolognesa.Series.Domain.ReadModels.Episode
  alias Bolognesa.Series.Domain.ValueObjects.SeasonEntry

  @type t :: %__MODULE__{
          season_id: pos_integer(),
          season_number: non_neg_integer(),
          number: pos_integer(),
          episode_id: Episode.id(),
          part_number: SeasonEntry.part_number(),
          available?: boolean(),
          last_watched_at: DateTime.t() | nil
        }
  @enforce_keys [:season_id, :season_number, :number, :episode_id, :part_number, :available?]
  defstruct [
    :season_id,
    :season_number,
    :number,
    :episode_id,
    :part_number,
    :available?,
    :last_watched_at
  ]

  @spec season_entry(t()) :: SeasonEntry.t()
  def season_entry(status),
    do: %SeasonEntry{episode_id: status.episode_id, part_number: status.part_number}
end
