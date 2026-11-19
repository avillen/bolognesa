defmodule Bolognesa.Series.Domain.ReadModels.WatchedEntry do
  @moduledoc "The account's latest watched timestamp for a season entry, independent of files."
  alias Bolognesa.Series.Domain.ValueObjects.SeasonEntry

  @type last_watched_at :: DateTime.t()
  @type t :: %__MODULE__{
          season_entry: SeasonEntry.t(),
          last_watched_at: last_watched_at()
        }
  @enforce_keys [:season_entry, :last_watched_at]
  defstruct [:season_entry, :last_watched_at]
end
