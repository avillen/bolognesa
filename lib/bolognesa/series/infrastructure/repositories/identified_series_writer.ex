defmodule Bolognesa.Series.Infrastructure.Repositories.IdentifiedSeriesWriter do
  @moduledoc false
  import Ecto.Query
  alias Bolognesa.Infrastructure.Persistence.EpisodeSchema
  alias Bolognesa.Infrastructure.Persistence.SeasonSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationEpisodeSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesSchema
  alias Bolognesa.Repo
  alias Bolognesa.Series.Domain.ValueObjects.EpisodeSelection
  alias Bolognesa.Series.Infrastructure.Repositories.EctoIdentificationRepository.DecisionStore

  @spec delete_orphaned!([pos_integer()]) :: :ok
  def delete_orphaned!(ids) do
    Enum.each(ids, &delete_orphaned_episode!/1)
    :ok
  end

  defp delete_orphaned_episode!(id) do
    case Repo.get(EpisodeSchema, id, log: false) do
      nil -> :ok
      episode -> delete_episode_and_empty_parents!(episode)
    end
  end

  defp delete_episode_and_empty_parents!(episode) do
    parent =
      from(season in SeasonSchema,
        where: season.id == ^episode.season_id,
        select: season.series_id
      )

    Repo.one(
      from(series in SeriesSchema, where: series.id in subquery(parent), lock: "FOR UPDATE"),
      log: false
    )

    references = from(row in SeriesIdentificationEpisodeSchema, select: row.episode_id)

    {count, _} =
      Repo.delete_all(
        from(row in EpisodeSchema,
          where: row.id == ^episode.id and row.id not in subquery(references)
        ),
        log: false
      )

    if count == 1 do
      delete_empty_season!(episode.season_id)
    end
  end

  defp delete_empty_season!(id) do
    season = Repo.get!(SeasonSchema, id, log: false)
    occupied = from(row in EpisodeSchema, select: row.season_id)

    {count, _} =
      Repo.delete_all(
        from(row in SeasonSchema, where: row.id == ^id and row.id not in subquery(occupied)),
        log: false
      )

    if count == 1 do
      delete_empty_series!(season.series_id)
    end
  end

  defp delete_empty_series!(id) do
    occupied = from(row in SeasonSchema, select: row.series_id)

    {_count, _} =
      Repo.delete_all(
        from(row in SeriesSchema, where: row.id == ^id and row.id not in subquery(occupied)),
        log: false
      )

    :ok
  end

  @spec upsert!(EpisodeSelection.t()) :: [pos_integer()]
  @spec upsert!(EpisodeSelection.t(), DecisionStore.repo()) :: [pos_integer()]
  def upsert!(%EpisodeSelection{} = selection, repo \\ Repo) do
    {:ok, validated} =
      EpisodeSelection.new(
        selection.series,
        selection.season,
        Enum.map(selection.episodes, & &1.number)
      )

    series_id = persist!(repo, SeriesSchema, Map.from_struct(validated.series))

    season_id =
      persist!(repo, SeasonSchema, %{
        provider_id: validated.season.provider_id,
        series_id: series_id,
        number: validated.season.number,
        title: validated.season.title,
        poster_path: validated.season.poster_path
      })

    season = repo.get!(SeasonSchema, season_id, log: false)
    true = season.series_id == series_id and season.number == validated.season.number

    Enum.map(validated.episodes, fn episode ->
      attrs =
        episode
        |> Map.from_struct()
        |> Map.drop([:season_number])
        |> Map.put(:season_id, season_id)

      id = persist!(repo, EpisodeSchema, attrs)
      stored = repo.get!(EpisodeSchema, id, log: false)
      true = stored.season_id == season_id and stored.number == episode.number
      id
    end)
  end

  defp persist!(repo, schema, attrs) do
    row =
      repo.insert!(schema.changeset(struct(schema), Map.put(attrs, :provider, :tmdb)),
        on_conflict: [set: [provider_id: attrs.provider_id]],
        conflict_target: [:provider, :provider_id],
        returning: true,
        log: false
      )

    row.id
  end
end
