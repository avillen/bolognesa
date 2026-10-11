defmodule Bolognesa.Identification.Infrastructure.Persistence.IdentifiedSeriesWriter do
  @moduledoc false
  alias Bolognesa.Identification.Domain.EpisodeSelection

  alias Bolognesa.Infrastructure.Persistence.{
    CatalogEntrySchema,
    EpisodeSchema,
    SeasonSchema,
    SeriesSchema
  }

  alias Bolognesa.Repo

  @spec upsert!(EpisodeSelection.t()) :: [pos_integer()]
  def upsert!(%EpisodeSelection{} = selection) do
    {:ok, validated} =
      EpisodeSelection.new(
        selection.series,
        selection.season,
        Enum.map(selection.episodes, & &1.number)
      )

    series_id = identity!(:series, validated.series.provider_id)

    persist!(
      SeriesSchema,
      series_id,
      Map.from_struct(validated.series) |> Map.delete(:provider_id)
    )

    season_id = identity!(:season, validated.season.provider_id)

    persist!(SeasonSchema, season_id, %{
      series_id: series_id,
      number: validated.season.number,
      title: validated.season.title,
      poster_path: validated.season.poster_path
    })

    season = Repo.get!(SeasonSchema, season_id, log: false)
    true = season.series_id == series_id and season.number == validated.season.number

    Enum.map(validated.episodes, fn episode ->
      id = identity!(:episode, episode.provider_id)

      attrs =
        episode
        |> Map.from_struct()
        |> Map.drop([:provider_id, :season_number])
        |> Map.put(:season_id, season_id)

      persist!(EpisodeSchema, id, attrs)
      stored = Repo.get!(EpisodeSchema, id, log: false)
      true = stored.season_id == season_id and stored.number == episode.number
      id
    end)
  end

  defp identity!(kind, provider_id) do
    attrs = %{kind: kind, resource_type: kind, provider: :tmdb, provider_id: provider_id}

    Repo.insert!(CatalogEntrySchema.changeset(%CatalogEntrySchema{}, attrs),
      on_conflict: :nothing,
      conflict_target: [:provider, :resource_type, :provider_id],
      log: false
    )

    row =
      Repo.get_by!(CatalogEntrySchema, Map.take(attrs, [:provider, :resource_type, :provider_id]),
        log: false
      )

    true = row.kind == kind
    row.id
  end

  defp persist!(schema, id, attrs) do
    Repo.insert!(schema.changeset(struct(schema, id: id), attrs),
      on_conflict: :nothing,
      conflict_target: [:id],
      log: false
    )
  end
end
