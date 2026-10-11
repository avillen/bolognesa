defmodule Bolognesa.Catalog.Infrastructure.Readers.EctoSeriesReader.SeriesMapper do
  @moduledoc false
  alias Bolognesa.Catalog.Domain.{Episode, Season, Series}

  alias Bolognesa.Infrastructure.Persistence.{
    CatalogEntrySchema,
    EpisodeSchema,
    SeasonSchema,
    SeriesSchema
  }

  @spec series(SeriesSchema.t(), CatalogEntrySchema.t()) :: Series.t()
  def series(row, entry),
    do:
      struct(
        Series,
        Map.take(Map.from_struct(row), [
          :id,
          :title,
          :year,
          :overview,
          :poster_path,
          :backdrop_path
        ])
        |> Map.merge(%{provider: entry.provider, provider_id: entry.provider_id})
      )

  @spec season(SeasonSchema.t()) :: Season.t()
  def season(row),
    do:
      struct(
        Season,
        Map.take(Map.from_struct(row), [:id, :series_id, :number, :title, :poster_path])
      )

  @spec episode(EpisodeSchema.t()) :: Episode.t()
  def episode(row),
    do:
      struct(
        Episode,
        Map.take(Map.from_struct(row), [
          :id,
          :season_id,
          :number,
          :title,
          :overview,
          :air_date,
          :still_path
        ])
      )
end
