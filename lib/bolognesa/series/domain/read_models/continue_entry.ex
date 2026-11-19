defmodule Bolognesa.Series.Domain.ReadModels.ContinueEntry do
  @moduledoc "A regular season entry in series order with the account's latest watched date, if any."
  alias Bolognesa.Series.Domain.ReadModels.Episode
  alias Bolognesa.Series.Domain.ValueObjects.SeasonEntry

  @type t :: %__MODULE__{
          season_number: pos_integer(),
          number: pos_integer(),
          episode_id: Episode.id(),
          part_number: SeasonEntry.part_number(),
          available?: boolean(),
          last_watched_at: DateTime.t() | nil
        }
  @enforce_keys [:season_number, :number, :episode_id, :part_number, :available?]
  defstruct [:season_number, :number, :episode_id, :part_number, :available?, :last_watched_at]
end
