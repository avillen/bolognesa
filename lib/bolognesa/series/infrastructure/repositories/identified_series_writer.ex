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

  @spec upsert!(EpisodeSelection.t(), DecisionStore.repo()) :: [pos_integer()]
  def upsert!(%EpisodeSelection{} = selection, repo \\ Repo) do
    series = persist!(repo, SeriesSchema, Map.from_struct(selection.series))

    season =
      persist!(repo, SeasonSchema, %{
        provider_id: selection.season.provider_id,
        series_id: series.id,
        number: selection.season.number,
        title: selection.season.title,
        poster_path: selection.season.poster_path
      })

    consistent!(repo, season.series_id == series.id and season.number == selection.season.number)

    Enum.map(selection.episodes, fn episode ->
      attrs =
        episode
        |> Map.from_struct()
        |> Map.drop([:season_number])
        |> Map.put(:season_id, season.id)

      stored = persist!(repo, EpisodeSchema, attrs)
      consistent!(repo, stored.season_id == season.id and stored.number == episode.number)
      stored.id
    end)
  end

  # TMDb can move a known provider_id to another season or number (common with specials).
  defp consistent!(_repo, true), do: :ok
  defp consistent!(repo, false), do: repo.rollback(:invalid_response)

  defp persist!(repo, schema, attrs) do
    repo.insert!(schema.changeset(struct(schema), Map.put(attrs, :provider, :tmdb)),
      on_conflict: [set: [provider_id: attrs.provider_id]],
      conflict_target: [:provider, :provider_id],
      returning: true,
      log: false
    )
  end
end
