defmodule Bolognesa.Series.Infrastructure.Readers.EctoSeriesReader.SeriesMapper do
  @moduledoc false
  alias Bolognesa.Infrastructure.Persistence.EpisodeSchema
  alias Bolognesa.Infrastructure.Persistence.SeasonSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesSchema
  alias Bolognesa.Series.Domain.ReadModels.Episode
  alias Bolognesa.Series.Domain.ReadModels.Season
  alias Bolognesa.Series.Domain.ReadModels.Series

  @spec series(SeriesSchema.t()) :: Series.t()
  def series(row),
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
        |> Map.merge(%{provider: row.provider, provider_id: row.provider_id})
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
