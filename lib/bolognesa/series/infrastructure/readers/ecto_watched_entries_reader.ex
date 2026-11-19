defmodule Bolognesa.Series.Infrastructure.Readers.EctoWatchedEntriesReader do
  @moduledoc false
  @behaviour Bolognesa.Series.Application.Ports.Readers.WatchedEntriesReader
  import Ecto.Query
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationEpisodeSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationSchema
  alias Bolognesa.Repo
  alias Bolognesa.Series.Domain.ReadModels.WatchedEntry
  alias Bolognesa.Series.Domain.ValueObjects.SeasonEntry
  alias Bolognesa.Series.Infrastructure.Readers.EpisodeEntries

  @max_entries 10_000

  @impl true
  def list_watched_entries(user_id, scope) do
    case scope_filter(scope) do
      {:ok, filter, ids} -> read_watched(user_id, filter, ids)
      error -> error
    end
  end

  defp read_watched(user_id, filter, ids) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT watched.episode_id, watched.part_number, watched.last_watched_at
        FROM series_watched_entries AS watched
        JOIN episodes AS episode ON episode.id = watched.episode_id
        JOIN seasons AS season ON season.id = episode.season_id
        WHERE watched.user_id = $1 AND #{filter}
        ORDER BY watched.episode_id, watched.part_number NULLS FIRST
        LIMIT 10001
        """,
        [user_id, ids],
        log: false
      )

    bounded(rows, fn [episode_id, part, timestamp] ->
      %WatchedEntry{
        episode_id: episode_id,
        part_number: part,
        last_watched_at: DateTime.from_naive!(timestamp, "Etc/UTC")
      }
    end)
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp scope_filter({:episode, id}), do: {:ok, "episode.id = ANY($2::bigint[])", [id]}
  defp scope_filter({:season, id}), do: {:ok, "season.id = ANY($2::bigint[])", [id]}

  defp scope_filter({:series, ids}) when is_list(ids) and length(ids) > 100,
    do: {:error, :too_many_entries}

  defp scope_filter({:series, ids}) when is_list(ids),
    do: {:ok, "season.series_id = ANY($2::bigint[])", Enum.uniq(ids)}

  defp scope_filter({:series, id}), do: scope_filter({:series, [id]})

  @impl true
  def list_played_entries(episode_id, file_id) do
    # The guard association prevents a file from another episode selecting its entries.
    decisions =
      from relation in SeriesIdentificationEpisodeSchema,
        where: relation.episode_id == ^episode_id,
        select: relation.identification_id

    rows =
      Repo.all(
        from(relation in SeriesIdentificationEpisodeSchema,
          join: decision in SeriesIdentificationSchema,
          on: decision.id == relation.identification_id,
          join: file in MediaFileSchema,
          on: file.id == decision.media_file_id,
          join: entry in subquery(EpisodeEntries.query()),
          on: entry.id == relation.episode_id,
          where:
            decision.id in subquery(decisions) and file.id == ^file_id and
              file.availability == :available and decision.state in [:automatic, :manual] and
              (is_nil(decision.part_number) or decision.part_number == entry.part_number),
          order_by: [entry.id, asc_nulls_first: entry.part_number],
          limit: ^(@max_entries + 1),
          select: {entry.id, entry.part_number}
        ),
        log: false
      )

    case rows do
      [] -> :not_found
      rows -> bounded(rows, fn {id, part} -> %SeasonEntry{episode_id: id, part_number: part} end)
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp bounded(rows, _mapper) when length(rows) > @max_entries, do: {:error, :too_many_entries}
  defp bounded(rows, mapper), do: {:ok, Enum.map(rows, mapper)}
end
