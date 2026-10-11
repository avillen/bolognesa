defmodule Bolognesa.Identification.Infrastructure.Readers.EctoSeriesReviewReader do
  @moduledoc false
  @behaviour Bolognesa.Identification.Application.Ports.Readers.SeriesReviewReader
  import Ecto.Query
  alias Bolognesa.Identification.Domain.ReadModels.{ReviewEpisode, ReviewSeriesFile}
  alias Bolognesa.Identification.Domain.ValueObjects.Series.SeriesCandidate
  alias Bolognesa.Identification.Infrastructure.Repositories.IdentificationMapper

  alias Bolognesa.Infrastructure.Persistence.{
    CatalogEntrySchema,
    EpisodeSchema,
    IdentificationEntrySchema,
    IdentificationSchema,
    LibrarySchema,
    MediaFileSchema,
    SeasonSchema,
    SeriesSchema
  }

  alias Bolognesa.Repo

  @impl true
  def list_series_review_items(page) do
    base =
      from decision in IdentificationSchema,
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

    values = Enum.map(rows, &review_row/1)
    {:ok, {values, total}}
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  @impl true
  def get_series_review_item(id) do
    row =
      Repo.one(
        from decision in IdentificationSchema,
          join: file in MediaFileSchema,
          on: file.id == decision.media_file_id,
          join: library in LibrarySchema,
          on: library.id == file.library_id,
          where: file.id == ^id and library.content_type == :series,
          select: {decision, file},
          limit: 1
      )

    case row do
      nil -> {:error, :not_found}
      value -> {:ok, review_row(value)}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp review_row({decision, file}) do
    episodes =
      Repo.all(
        from(relation in IdentificationEntrySchema,
          join: episode in EpisodeSchema,
          on: episode.id == relation.catalog_entry_id,
          join: season in SeasonSchema,
          on: season.id == episode.season_id,
          join: series in SeriesSchema,
          on: series.id == season.series_id,
          join: entry in CatalogEntrySchema,
          on: entry.id == series.id,
          where: relation.identification_id == ^decision.id,
          order_by: relation.position,
          select: {episode, season, series, entry}
        ),
        log: false
      )
      |> Enum.map(fn {episode, season, series, entry} ->
        %ReviewEpisode{
          id: episode.id,
          number: episode.number,
          season_number: season.number,
          series_title: series.title,
          series_provider_id: entry.provider_id
        }
      end)

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
