defmodule Bolognesa.Series.Application.Ports.Repositories.WatchedEntriesRepository do
  @moduledoc "Atomic account-scoped writes for explicit entries; no inventory references."
  alias Bolognesa.Series.Domain.ValueObjects.Entry

  @type adapter :: module()
  @type result :: :ok | {:error, :unavailable}

  @doc "Atomically upsert explicit entries, retaining the greatest timestamp. Empty is a no-op."
  @callback upsert(user_id :: pos_integer(), [Entry.t()], DateTime.t()) ::
              result()

  @doc "Delete one explicit entry for the account. A missing row is a no-op."
  @callback delete(user_id :: pos_integer(), Entry.t()) :: result()
end
