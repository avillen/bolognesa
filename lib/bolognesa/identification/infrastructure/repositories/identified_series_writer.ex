defmodule Bolognesa.Identification.Infrastructure.Repositories.IdentifiedSeriesWriter do
  @moduledoc false
  import Ecto.Query
  alias Bolognesa.Identification.Domain.ValueObjects.Series.EpisodeSelection

  alias Bolognesa.Identification.Infrastructure.Repositories.EctoIdentificationRepository.DecisionStore

  alias Bolognesa.Infrastructure.Persistence.{
    CatalogEntrySchema,
    EpisodeSchema,
    IdentificationEntrySchema,
    SeasonSchema,
    SeriesSchema
  }

  alias Bolognesa.Repo

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

    references = from(row in IdentificationEntrySchema, select: row.catalog_entry_id)

    {count, _} =
      Repo.delete_all(
        from(row in EpisodeSchema,
          where: row.id == ^episode.id and row.id not in subquery(references)
        ),
        log: false
      )

    if count == 1 do
      delete_identity!(episode.id)
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
      delete_identity!(id)
      delete_empty_series!(season.series_id)
    end
  end

  defp delete_empty_series!(id) do
    occupied = from(row in SeasonSchema, select: row.series_id)

    {count, _} =
      Repo.delete_all(
        from(row in SeriesSchema, where: row.id == ^id and row.id not in subquery(occupied)),
        log: false
      )

    if count == 1, do: delete_identity!(id)
  end

  defp delete_identity!(id) do
    Repo.delete_all(from(row in CatalogEntrySchema, where: row.id == ^id), log: false)
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

    series_id = identity!(repo, :series, validated.series.provider_id)

    persist!(
      repo,
      SeriesSchema,
      series_id,
      Map.from_struct(validated.series) |> Map.delete(:provider_id)
    )

    season_id = identity!(repo, :season, validated.season.provider_id)

    persist!(repo, SeasonSchema, season_id, %{
      series_id: series_id,
      number: validated.season.number,
      title: validated.season.title,
      poster_path: validated.season.poster_path
    })

    season = repo.get!(SeasonSchema, season_id, log: false)
    true = season.series_id == series_id and season.number == validated.season.number

    Enum.map(validated.episodes, fn episode ->
      id = identity!(repo, :episode, episode.provider_id)

      attrs =
        episode
        |> Map.from_struct()
        |> Map.drop([:provider_id, :season_number])
        |> Map.put(:season_id, season_id)

      persist!(repo, EpisodeSchema, id, attrs)
      stored = repo.get!(EpisodeSchema, id, log: false)
      true = stored.season_id == season_id and stored.number == episode.number
      id
    end)
  end

  defp identity!(repo, kind, provider_id) do
    attrs = %{kind: kind, resource_type: kind, provider: :tmdb, provider_id: provider_id}

    row =
      repo.insert!(CatalogEntrySchema.changeset(%CatalogEntrySchema{}, attrs),
        on_conflict: [set: [provider_id: provider_id]],
        conflict_target: [:provider, :resource_type, :provider_id],
        returning: true,
        log: false
      )

    true = row.kind == kind
    row.id
  end

  defp persist!(repo, schema, id, attrs) do
    repo.insert!(schema.changeset(struct(schema, id: id), attrs),
      on_conflict: :nothing,
      conflict_target: [:id],
      log: false
    )
  end
end
