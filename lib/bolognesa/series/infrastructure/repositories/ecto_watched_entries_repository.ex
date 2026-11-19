defmodule Bolognesa.Series.Infrastructure.Repositories.EctoWatchedEntriesRepository do
  @moduledoc false
  @behaviour Bolognesa.Series.Application.Ports.Repositories.WatchedEntriesRepository
  alias Bolognesa.Repo

  @impl true
  def upsert(user_id, entries, watched_at) do
    write(entries, fn batch ->
      Repo.query!(
        """
        INSERT INTO series_watched_entries (user_id, episode_id, part_number, last_watched_at)
        SELECT $1, entry.episode_id, entry.part_number, $4
        FROM unnest($2::bigint[], $3::integer[]) AS entry(episode_id, part_number)
        ON CONFLICT (user_id, episode_id, part_number) DO UPDATE
        SET last_watched_at = GREATEST(series_watched_entries.last_watched_at, EXCLUDED.last_watched_at)
        """,
        [
          user_id,
          Enum.map(batch, & &1.episode_id),
          Enum.map(batch, & &1.part_number),
          watched_at
        ],
        log: false
      )
    end)
  end

  @impl true
  def delete(user_id, entries) do
    write(entries, fn batch ->
      Repo.query!(
        """
        DELETE FROM series_watched_entries AS watched
        USING unnest($2::bigint[], $3::integer[]) AS entry(episode_id, part_number)
        WHERE watched.user_id = $1 AND watched.episode_id = entry.episode_id
          AND watched.part_number IS NOT DISTINCT FROM entry.part_number
        """,
        [user_id, Enum.map(batch, & &1.episode_id), Enum.map(batch, & &1.part_number)],
        log: false
      )
    end)
  end

  defp write(entries, operation) do
    case Enum.uniq(entries) do
      [] ->
        :ok

      entries ->
        operation.(entries)
        :ok
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end
end
