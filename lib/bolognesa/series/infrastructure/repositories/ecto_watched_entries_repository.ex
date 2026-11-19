defmodule Bolognesa.Series.Infrastructure.Repositories.EctoWatchedEntriesRepository do
  @moduledoc false
  @behaviour Bolognesa.Series.Application.Ports.Repositories.WatchedEntriesRepository
  import Ecto.Query
  alias Bolognesa.Infrastructure.Persistence.SeriesWatchedEntrySchema
  alias Bolognesa.Repo

  @impl true
  def upsert(user_id, entries, watched_at) do
    rows =
      entries
      |> Enum.uniq()
      |> Enum.map(fn entry ->
        %{
          user_id: user_id,
          episode_id: entry.episode_id,
          part_number: entry.part_number,
          last_watched_at: watched_at
        }
      end)

    on_conflict =
      from watched in SeriesWatchedEntrySchema,
        update: [
          set: [
            last_watched_at:
              fragment("GREATEST(?, EXCLUDED.last_watched_at)", watched.last_watched_at)
          ]
        ]

    Repo.insert_all(SeriesWatchedEntrySchema, rows,
      on_conflict: on_conflict,
      conflict_target: [:user_id, :episode_id, :part_number],
      log: false
    )

    :ok
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end
end
