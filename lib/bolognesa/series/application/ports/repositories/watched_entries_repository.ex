defmodule Bolognesa.Series.Application.Ports.Repositories.WatchedEntriesRepository do
  @moduledoc "Atomic account-scoped writes for explicit season entries; no inventory references."
  alias Bolognesa.Series.Domain.ReadModels.WatchedEntry
  alias Bolognesa.Series.Domain.ValueObjects.SeasonEntry

  @type adapter :: module()
  @type result :: :ok | {:error, :unavailable}

  @doc "Atomically upsert explicit entries, retaining the greatest timestamp. Empty is a no-op."
  @callback upsert(user_id :: pos_integer(), [SeasonEntry.t()], WatchedEntry.last_watched_at()) ::
              result()

  @doc "Atomically delete explicit entries for this account only. Empty is a no-op."
  @callback delete(user_id :: pos_integer(), [SeasonEntry.t()]) :: result()
end
