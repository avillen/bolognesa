defmodule Bolognesa.Series.Domain.ReadModels.WatchedEntry do
  @moduledoc "The account's latest watched timestamp for a season entry, independent of files."
  alias Bolognesa.Series.Domain.ReadModels.Episode
  alias Bolognesa.Series.Domain.ValueObjects.SeasonEntry

  @type last_watched_at :: DateTime.t()
  @type t :: %__MODULE__{
          episode_id: Episode.id(),
          part_number: SeasonEntry.part_number(),
          last_watched_at: last_watched_at()
        }
  @enforce_keys [:episode_id, :part_number, :last_watched_at]
  defstruct [:episode_id, :part_number, :last_watched_at]
end
