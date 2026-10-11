defmodule Bolognesa.Catalog.Infrastructure.Persistence.EctoSeriesReader do
  @moduledoc false
  @behaviour Bolognesa.Catalog.Application.Ports.SeriesReader
  import Ecto.Query
  alias Bolognesa.Catalog.Domain.EpisodeVersion
  alias Bolognesa.Catalog.Infrastructure.Persistence.EctoSeriesReader.SeriesMapper

  alias Bolognesa.Infrastructure.Persistence.{
    CatalogEntrySchema,
    EpisodeSchema,
    IdentificationEntrySchema,
    IdentificationSchema,
    InspectionSchema,
    MediaFileSchema,
    SeasonSchema,
    SeriesSchema
  }

  alias Bolognesa.Repo
  @page_size 24

  @impl true
  def list_series(query, page) do
    base =
      from series in SeriesSchema,
        where: fragment("strpos(lower(?), lower(?)) > 0", series.title, ^query)

    total = Repo.aggregate(base, :count, :id, log: false)

    rows =
      Repo.all(
        from(series in base,
          join: entry in CatalogEntrySchema,
          on: entry.id == series.id and entry.kind == :series,
          left_join: season in SeasonSchema,
          on: season.series_id == series.id,
          left_join: episode in EpisodeSchema,
          on: episode.season_id == season.id,
          left_join: relation in IdentificationEntrySchema,
          on: relation.catalog_entry_id == episode.id,
          left_join: decision in IdentificationSchema,
          on:
            decision.id == relation.identification_id and decision.state in [:automatic, :manual],
          left_join: file in MediaFileSchema,
          on: file.id == decision.media_file_id,
          group_by: [series.id, entry.id],
          order_by: [asc: series.title, asc: series.id],
          limit: @page_size,
          offset: ^((page - 1) * @page_size),
          select:
            {series, entry, count(episode.id, :distinct),
             filter(count(episode.id, :distinct), file.availability == :available)}
        ),
        log: false
      )

    {:ok,
     {Enum.map(rows, fn {series, entry, count, available} ->
        {SeriesMapper.series(series, entry), count, available}
      end), total}}
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  @impl true
  def get_series(id) do
    case series_row(id) do
      nil ->
        {:error, :not_found}

      {series, entry} ->
        seasons =
          Repo.all(
            from(season in SeasonSchema,
              left_join: episode in EpisodeSchema,
              on: episode.season_id == season.id,
              where: season.series_id == ^id,
              group_by: season.id,
              order_by: season.number,
              select: {season, count(episode.id)}
            ),
            log: false
          )

        {:ok,
         {SeriesMapper.series(series, entry),
          Enum.map(seasons, fn {season, count} -> {SeriesMapper.season(season), count} end)}}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  @impl true
  def list_episodes(id, page) do
    case Repo.get(SeasonSchema, id, log: false) do
      nil -> {:error, :not_found}
      season -> list_season_episodes(season, page)
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp list_season_episodes(season, page) do
    base = from episode in EpisodeSchema, where: episode.season_id == ^season.id
    total = Repo.aggregate(base, :count)

    rows =
      Repo.all(
        from(episode in base,
          left_join: relation in IdentificationEntrySchema,
          on: relation.catalog_entry_id == episode.id,
          left_join: decision in IdentificationSchema,
          on:
            decision.id == relation.identification_id and decision.state in [:automatic, :manual],
          left_join: file in MediaFileSchema,
          on: file.id == decision.media_file_id,
          group_by: episode.id,
          order_by: [asc: episode.number, asc: episode.id],
          limit: @page_size,
          offset: ^((page - 1) * @page_size),
          select:
            {episode, count(file.id, :distinct),
             filter(count(file.id, :distinct), file.availability == :available)}
        ),
        log: false
      )

    {series, entry} = series_row(season.series_id)

    {:ok,
     {SeriesMapper.season(season), SeriesMapper.series(series, entry),
      Enum.map(rows, fn {episode, count, available} ->
        {SeriesMapper.episode(episode), count, available}
      end), total}}
  end

  @impl true
  def get_episode(id) do
    row =
      Repo.one(
        from(episode in EpisodeSchema,
          join: season in SeasonSchema,
          on: season.id == episode.season_id,
          join: series in SeriesSchema,
          on: series.id == season.series_id,
          join: entry in CatalogEntrySchema,
          on: entry.id == series.id,
          where: episode.id == ^id,
          select: {episode, season, series, entry}
        ),
        log: false
      )

    case row do
      nil ->
        {:error, :not_found}

      {episode, season, series, entry} ->
        {:ok,
         {SeriesMapper.episode(episode), SeriesMapper.season(season),
          SeriesMapper.series(series, entry), versions(id)}}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp versions(id) do
    rows =
      Repo.all(
        from(relation in IdentificationEntrySchema,
          join: decision in IdentificationSchema,
          on: decision.id == relation.identification_id,
          join: file in MediaFileSchema,
          on: file.id == decision.media_file_id,
          left_join: inspection in InspectionSchema,
          on:
            inspection.media_file_id == file.id and inspection.state == :succeeded and
              inspection.observed_revision == file.revision,
          where: relation.catalog_entry_id == ^id and decision.state in [:automatic, :manual],
          order_by: file.id,
          select: {decision, file, inspection}
        ),
        log: false
      )

    Enum.map(rows, fn {decision, file, inspection} ->
      numbers =
        Repo.all(
          from(relation in IdentificationEntrySchema,
            join: episode in EpisodeSchema,
            on: episode.id == relation.catalog_entry_id,
            where: relation.identification_id == ^decision.id,
            order_by: relation.position,
            select: episode.number
          ),
          log: false
        )

      %EpisodeVersion{
        id: file.id,
        availability: file.availability,
        size_bytes: file.size_bytes,
        origin: decision.origin,
        needs_review?: decision.needs_review,
        episode_numbers: numbers,
        format: if(inspection, do: inspection.format),
        duration_ms: if(inspection, do: inspection.duration_ms),
        codecs: if(inspection, do: codecs(inspection.tracks), else: [])
      }
    end)
  end

  defp codecs(%{"items" => items}) when is_list(items) do
    items
    |> Enum.flat_map(fn
      %{"codec" => codec} when is_binary(codec) -> [codec]
      _ -> []
    end)
    |> Enum.uniq()
  end

  defp codecs(_), do: []

  defp series_row(id),
    do:
      Repo.one(
        from(series in SeriesSchema,
          join: entry in CatalogEntrySchema,
          on: entry.id == series.id and entry.kind == :series,
          where: series.id == ^id,
          select: {series, entry}
        ),
        log: false
      )
end
