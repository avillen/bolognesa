defmodule Bolognesa.Series.Infrastructure.Readers.EctoWatchedEntriesReader do
  @moduledoc false
  @behaviour Bolognesa.Series.Application.Ports.Readers.WatchedEntriesReader
  import Ecto.Query
  alias Bolognesa.Infrastructure.Persistence.SeasonSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationEpisodeSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesWatchedEntrySchema
  alias Bolognesa.Repo
  alias Bolognesa.Series.Domain.ReadModels.SeasonEntryStatus
  alias Bolognesa.Series.Domain.ValueObjects.SeasonEntry
  alias Bolognesa.Series.Infrastructure.Readers.ConfirmedFiles
  alias Bolognesa.Series.Infrastructure.Readers.EpisodeEntries

  @impl true
  def list_entries(user_id, scope) do
    entries =
      from(entry in subquery(EpisodeEntries.query()),
        join: season in SeasonSchema,
        on: season.id == entry.season_id,
        left_join: watched in SeriesWatchedEntrySchema,
        on:
          watched.episode_id == entry.id and watched.user_id == ^user_id and
            fragment("? IS NOT DISTINCT FROM ?", watched.part_number, entry.part_number),
        order_by: [season.number, entry.number, asc_nulls_first: entry.part_number],
        select: %SeasonEntryStatus{
          season_number: season.number,
          number: entry.number,
          episode_id: entry.id,
          part_number: entry.part_number,
          available?: entry.available_version_count > 0,
          last_watched_at: watched.last_watched_at
        }
      )
      |> in_scope(scope)
      |> Repo.all(log: false)

    {:ok, entries}
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp in_scope(query, {:episode, id}), do: where(query, [entry], entry.id == ^id)
  defp in_scope(query, {:season, id}), do: where(query, [entry], entry.season_id == ^id)

  defp in_scope(query, {:series, id}),
    do: where(query, [_entry, season], season.series_id == ^id)

  @impl true
  def fetch_played_entries(episode_id, file_id) do
    # The guard association prevents a file from another episode selecting its entries.
    decisions =
      from relation in SeriesIdentificationEpisodeSchema,
        where: relation.episode_id == ^episode_id,
        select: relation.identification_id

    rows =
      Repo.all(
        from([relation, decision, file] in ConfirmedFiles.query(),
          join: entry in subquery(EpisodeEntries.query()),
          on: entry.id == relation.episode_id,
          where:
            decision.id in subquery(decisions) and file.id == ^file_id and
              file.availability == :available and
              (is_nil(decision.part_number) or decision.part_number == entry.part_number),
          order_by: [entry.id, asc_nulls_first: entry.part_number],
          select: {entry.id, entry.part_number}
        ),
        log: false
      )

    case rows do
      [] ->
        :not_found

      rows ->
        {:ok,
         Enum.map(rows, fn {id, part} -> %SeasonEntry{episode_id: id, part_number: part} end)}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end
end
