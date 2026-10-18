defmodule Bolognesa.Series.Infrastructure.Readers.EctoSeriesReviewReader do
  @moduledoc false
  @behaviour Bolognesa.Series.Application.Ports.Readers.SeriesReviewReader
  import Ecto.Query
  alias Bolognesa.Infrastructure.Persistence.EpisodeSchema
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.SeasonSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationEpisodeSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesSchema
  alias Bolognesa.Repo
  alias Bolognesa.Series.Domain.ReadModels.ReviewEpisode
  alias Bolognesa.Series.Domain.ReadModels.ReviewSeriesFile
  alias Bolognesa.Series.Domain.ValueObjects.SeriesCandidate
  alias Bolognesa.Series.Infrastructure.Repositories.IdentificationMapper

  @impl true
  def list_series_review_items(page) do
    base =
      from decision in SeriesIdentificationSchema,
        join: file in MediaFileSchema,
        on: file.id == decision.media_file_id,
        join: library in LibrarySchema,
        on: library.id == file.library_id,
        where: library.content_type == :series,
        where:
          decision.state in [:pending, :unmatched, :failed, :manual_unidentified] or
            decision.needs_review

    total = Repo.aggregate(base, :count, :id)

    rows =
      Repo.all(
        from([decision, file] in base,
          order_by: file.id,
          limit: 24,
          offset: ^((page - 1) * 24),
          select: {decision, file}
        ),
        log: false
      )

    episodes = episodes_by_decision(Enum.map(rows, fn {decision, _file} -> decision.id end))

    values =
      Enum.map(rows, fn {decision, _file} = row ->
        review_row(row, Map.get(episodes, decision.id, []))
      end)

    {:ok, {values, total}}
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  @impl true
  def fetch_series_review_item(id) do
    row =
      Repo.one(
        from decision in SeriesIdentificationSchema,
          join: file in MediaFileSchema,
          on: file.id == decision.media_file_id,
          join: library in LibrarySchema,
          on: library.id == file.library_id,
          where: file.id == ^id and library.content_type == :series,
          select: {decision, file},
          limit: 1
      )

    case row do
      nil ->
        :not_found

      {decision, _file} = value ->
        episodes = episodes_by_decision([decision.id])
        {:ok, review_row(value, Map.get(episodes, decision.id, []))}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp episodes_by_decision([]), do: %{}

  defp episodes_by_decision(ids) do
    Repo.all(
      from(relation in SeriesIdentificationEpisodeSchema,
        join: episode in EpisodeSchema,
        on: episode.id == relation.episode_id,
        join: season in SeasonSchema,
        on: season.id == episode.season_id,
        join: series in SeriesSchema,
        on: series.id == season.series_id,
        where: relation.identification_id in ^ids,
        order_by: [relation.identification_id, relation.position],
        select: {relation.identification_id, episode, season, series}
      ),
      log: false
    )
    |> Enum.group_by(fn {id, _, _, _} -> id end, fn {_id, episode, season, series} ->
      %ReviewEpisode{
        id: episode.id,
        number: episode.number,
        season_number: season.number,
        series_title: series.title,
        series_provider_id: series.provider_id
      }
    end)
  end

  defp review_row({decision, file}, episodes) do
    {%ReviewSeriesFile{
       id: file.id,
       relative_path: file.relative_path,
       availability: file.availability,
       identification: IdentificationMapper.to_domain(decision, Enum.map(episodes, & &1.id)),
       candidates: candidates(decision.candidate_data)
     }, episodes}
  end

  defp candidates(%{"items" => items}) when is_list(items) do
    items |> Enum.take(5) |> Enum.flat_map(&candidate/1)
  end

  defp candidates(_), do: []

  defp candidate(raw) when is_map(raw) do
    attrs = %{
      provider_id: raw["provider_id"],
      title: raw["title"],
      year: raw["year"],
      poster_path: raw["poster_path"]
    }

    case SeriesCandidate.new(attrs) do
      {:ok, candidate} -> [candidate]
      _ -> []
    end
  end

  defp candidate(_), do: []
end
