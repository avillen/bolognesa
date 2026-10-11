defmodule Bolognesa.Identification.Infrastructure.Repositories.IdentifiedSeriesWriter do
  @moduledoc false
  alias Bolognesa.Identification.Domain.ValueObjects.Series.EpisodeSelection

  alias Bolognesa.Infrastructure.Persistence.{
    CatalogEntrySchema,
    EpisodeSchema,
    SeasonSchema,
    SeriesSchema
  }

  alias Bolognesa.Repo

  @spec upsert!(EpisodeSelection.t()) :: [pos_integer()]
  @spec upsert!(EpisodeSelection.t(), module()) :: [pos_integer()]
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

    repo.insert!(CatalogEntrySchema.changeset(%CatalogEntrySchema{}, attrs),
      on_conflict: :nothing,
      conflict_target: [:provider, :resource_type, :provider_id],
      log: false
    )

    row =
      repo.get_by!(CatalogEntrySchema, Map.take(attrs, [:provider, :resource_type, :provider_id]),
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
