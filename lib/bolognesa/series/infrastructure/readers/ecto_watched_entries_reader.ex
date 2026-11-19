defmodule Bolognesa.Series.Infrastructure.Readers.EctoWatchedEntriesReader do
  @moduledoc false
  @behaviour Bolognesa.Series.Application.Ports.Readers.WatchedEntriesReader
  import Ecto.Query
  alias Bolognesa.Infrastructure.Persistence.EpisodeSchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.SeasonSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationEpisodeSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesWatchedEntrySchema
  alias Bolognesa.Repo
  alias Bolognesa.Series.Domain.ReadModels.ContinueEntry
  alias Bolognesa.Series.Domain.ReadModels.WatchedEntry
  alias Bolognesa.Series.Domain.ValueObjects.SeasonEntry
  alias Bolognesa.Series.Infrastructure.Readers.EpisodeEntries

  @impl true
  def list_watched_entries(user_id, scope) do
    rows =
      from(watched in SeriesWatchedEntrySchema,
        join: episode in EpisodeSchema,
        on: episode.id == watched.episode_id,
        join: season in SeasonSchema,
        on: season.id == episode.season_id,
        where: watched.user_id == ^user_id,
        order_by: [watched.episode_id, asc_nulls_first: watched.part_number],
        select: {watched.episode_id, watched.part_number, watched.last_watched_at}
      )
      |> in_scope(scope)
      |> Repo.all(log: false)

    entries =
      Enum.map(rows, fn {episode_id, part, timestamp} ->
        %WatchedEntry{
          season_entry: %SeasonEntry{episode_id: episode_id, part_number: part},
          last_watched_at: timestamp
        }
      end)

    {:ok, entries}
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp in_scope(query, {:episode, id}), do: where(query, [watched], watched.episode_id == ^id)

  defp in_scope(query, {:season, id}),
    do: where(query, [_watched, episode], episode.season_id == ^id)

  defp in_scope(query, {:series, id}),
    do: where(query, [_watched, _episode, season], season.series_id == ^id)

  @impl true
  def list_continue_entries(user_id, series_id) do
    rows =
      Repo.all(
        from(entry in subquery(EpisodeEntries.query()),
          join: season in SeasonSchema,
          on: season.id == entry.season_id,
          left_join: watched in SeriesWatchedEntrySchema,
          on:
            watched.episode_id == entry.id and watched.user_id == ^user_id and
              fragment("? IS NOT DISTINCT FROM ?", watched.part_number, entry.part_number),
          where: season.series_id == ^series_id and season.number > 0,
          order_by: [season.number, entry.number, asc_nulls_first: entry.part_number],
          select: %ContinueEntry{
            season_number: season.number,
            number: entry.number,
            episode_id: entry.id,
            part_number: entry.part_number,
            available?: entry.available_version_count > 0,
            last_watched_at: watched.last_watched_at
          }
        ),
        log: false
      )

    {:ok, rows}
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  @impl true
  def list_season_entries(scope) do
    entries =
      from(entry in subquery(EpisodeEntries.query()),
        order_by: [entry.id, asc_nulls_first: entry.part_number],
        select: %SeasonEntry{episode_id: entry.id, part_number: entry.part_number}
      )
      |> entries_in(scope)
      |> Repo.all(log: false)

    {:ok, entries}
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp entries_in(query, {:episode, id}), do: where(query, [entry], entry.id == ^id)
  defp entries_in(query, {:season, id}), do: where(query, [entry], entry.season_id == ^id)

  @impl true
  def fetch_played_entries(episode_id, file_id) do
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
