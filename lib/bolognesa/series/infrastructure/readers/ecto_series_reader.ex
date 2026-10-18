defmodule Bolognesa.Series.Infrastructure.Readers.EctoSeriesReader do
  @moduledoc false
  @behaviour Bolognesa.Series.Application.Ports.Readers.SeriesReader
  import Ecto.Query
  alias Bolognesa.Infrastructure.Persistence.EpisodeSchema
  alias Bolognesa.Infrastructure.Persistence.InspectionSchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.SeasonSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationEpisodeSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesSchema
  alias Bolognesa.Repo
  alias Bolognesa.Series.Domain.ReadModels.EpisodeVersion
  alias Bolognesa.Series.Infrastructure.Readers.EctoSeriesReader.SeriesMapper

  @page_size 24
  @max_seasons 100
  @max_versions 100

  @impl true
  def list_series(query, page, library_id) do
    base =
      from series in SeriesSchema,
        where: fragment("strpos(lower(?), lower(?)) > 0", series.title, ^query)

    base = restrict_library(base, library_id)

    total = Repo.aggregate(base, :count, :id, log: false)

    rows =
      Repo.all(
        from(series in base,
          left_join: season in SeasonSchema,
          on: season.series_id == series.id,
          left_join: episode in EpisodeSchema,
          on: episode.season_id == season.id,
          left_join: relation in SeriesIdentificationEpisodeSchema,
          on: relation.episode_id == episode.id,
          left_join: decision in SeriesIdentificationSchema,
          on:
            decision.id == relation.identification_id and decision.state in [:automatic, :manual],
          left_join: file in MediaFileSchema,
          as: :file,
          on: file.id == decision.media_file_id,
          group_by: series.id,
          order_by: [asc: series.title, asc: series.id],
          limit: @page_size,
          offset: ^((page - 1) * @page_size),
          select:
            {series, count(episode.id, :distinct),
             filter(count(episode.id, :distinct), file.availability == :available)}
        )
        |> restrict_files(library_id),
        log: false
      )

    {:ok,
     {Enum.map(rows, fn {series, count, available} ->
        {SeriesMapper.series(series), count, available}
      end), total}}
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp restrict_library(query, nil), do: query

  defp restrict_library(query, library_id) do
    ids =
      from episode in EpisodeSchema,
        join: season in SeasonSchema,
        on: season.id == episode.season_id,
        join: relation in SeriesIdentificationEpisodeSchema,
        on: relation.episode_id == episode.id,
        join: decision in SeriesIdentificationSchema,
        on: decision.id == relation.identification_id,
        join: file in MediaFileSchema,
        on: file.id == decision.media_file_id,
        where: file.library_id == ^library_id and decision.state in [:automatic, :manual],
        select: season.series_id

    from entry in query, where: entry.id in subquery(ids)
  end

  defp restrict_files(query, nil), do: query

  defp restrict_files(query, library_id),
    do: from([file: file] in query, where: file.library_id == ^library_id)

  @impl true
  def fetch_series(id) do
    case series_row(id) do
      nil ->
        :not_found

      series ->
        seasons =
          Repo.all(
            from(season in SeasonSchema,
              left_join: episode in EpisodeSchema,
              on: episode.season_id == season.id,
              where: season.series_id == ^id,
              group_by: season.id,
              order_by: [asc: season.number, asc: season.id],
              limit: ^(@max_seasons + 1),
              select: {season, count(episode.id)}
            ),
            log: false
          )

        series_detail(series, seasons)
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp series_detail(_series, seasons) when length(seasons) > @max_seasons,
    do: {:error, :too_many_seasons}

  defp series_detail(series, seasons) do
    {:ok,
     {SeriesMapper.series(series),
      Enum.map(seasons, fn {season, count} -> {SeriesMapper.season(season), count} end)}}
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
          left_join: relation in SeriesIdentificationEpisodeSchema,
          on: relation.episode_id == episode.id,
          left_join: decision in SeriesIdentificationSchema,
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

    series = series_row(season.series_id)

    {:ok,
     {SeriesMapper.season(season), SeriesMapper.series(series),
      Enum.map(rows, fn {episode, count, available} ->
        {SeriesMapper.episode(episode), count, available}
      end), total}}
  end

  @impl true
  def fetch_episode(id) do
    row =
      Repo.one(
        from(episode in EpisodeSchema,
          join: season in SeasonSchema,
          on: season.id == episode.season_id,
          join: series in SeriesSchema,
          on: series.id == season.series_id,
          where: episode.id == ^id,
          select: {episode, season, series}
        ),
        log: false
      )

    case row do
      nil ->
        :not_found

      {episode, season, series} ->
        episode_detail(episode, season, series)
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  @impl true
  def fetch_next_episode(episode_id, file_id) do
    completed =
      from relation in SeriesIdentificationEpisodeSchema,
        join: decision in SeriesIdentificationSchema,
        on: decision.id == relation.identification_id,
        join: episode in EpisodeSchema,
        on: episode.id == relation.episode_id,
        join: season in SeasonSchema,
        on: season.id == episode.season_id,
        where: decision.media_file_id == ^file_id and decision.state in [:automatic, :manual],
        select: %{
          id: episode.id,
          number: episode.number,
          season_number: season.number,
          series_id: season.series_id
        }

    boundary =
      from row in subquery(completed),
        where: exists(from current in subquery(completed), where: current.id == ^episode_id),
        order_by: [desc: row.season_number, desc: row.number],
        limit: 1

    query =
      from episode in EpisodeSchema,
        join: season in SeasonSchema,
        on: season.id == episode.season_id,
        join: previous in subquery(boundary),
        on: previous.series_id == season.series_id,
        join: relation in SeriesIdentificationEpisodeSchema,
        on: relation.episode_id == episode.id,
        join: decision in SeriesIdentificationSchema,
        on: decision.id == relation.identification_id,
        join: file in MediaFileSchema,
        on: file.id == decision.media_file_id,
        where: decision.state in [:automatic, :manual] and file.availability == :available,
        where:
          season.number > previous.season_number or
            (season.number == previous.season_number and episode.number > previous.number),
        order_by: [asc: season.number, asc: episode.number, asc: episode.id],
        limit: 1,
        select: episode

    next_episode(Repo.one(query, log: false))
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp next_episode(nil), do: :not_found
  defp next_episode(episode), do: {:ok, SeriesMapper.episode(episode)}

  defp episode_detail(episode, season, series) do
    with {:ok, versions} <- versions(episode.id) do
      {:ok,
       {SeriesMapper.episode(episode), SeriesMapper.season(season), SeriesMapper.series(series),
        versions}}
    end
  end

  defp versions(id) do
    rows =
      Repo.all(
        from(relation in SeriesIdentificationEpisodeSchema,
          join: decision in SeriesIdentificationSchema,
          on: decision.id == relation.identification_id,
          join: file in MediaFileSchema,
          on: file.id == decision.media_file_id,
          left_join: inspection in InspectionSchema,
          on:
            inspection.media_file_id == file.id and inspection.state == :succeeded and
              inspection.observed_revision == file.revision,
          where: relation.episode_id == ^id and decision.state in [:automatic, :manual],
          limit: ^(@max_versions + 1),
          order_by: file.id,
          select: {decision, file, inspection}
        ),
        log: false
      )

    bounded_versions(rows)
  end

  defp bounded_versions(rows) when length(rows) > @max_versions, do: {:error, :too_many_versions}

  defp bounded_versions(rows) do
    numbers_by_decision = episode_numbers(rows)

    versions =
      Enum.map(rows, fn {decision, file, inspection} ->
        %EpisodeVersion{
          id: file.id,
          availability: file.availability,
          size_bytes: file.size_bytes,
          origin: decision.origin,
          needs_review?: decision.needs_review,
          episode_numbers: Map.get(numbers_by_decision, decision.id, []),
          format: if(inspection, do: inspection.format),
          duration_ms: if(inspection, do: inspection.duration_ms),
          codecs: if(inspection, do: codecs(inspection.tracks), else: [])
        }
      end)

    {:ok, versions}
  end

  defp episode_numbers([]), do: %{}

  defp episode_numbers(rows) do
    decision_ids = Enum.map(rows, fn {decision, _file, _inspection} -> decision.id end)

    Repo.all(
      from(relation in SeriesIdentificationEpisodeSchema,
        join: episode in EpisodeSchema,
        on: episode.id == relation.episode_id,
        where: relation.identification_id in ^decision_ids,
        order_by: [relation.identification_id, relation.position],
        select: {relation.identification_id, episode.number}
      ),
      log: false
    )
    |> Enum.group_by(fn {id, _number} -> id end, fn {_id, number} -> number end)
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
          where: series.id == ^id,
          select: series
        ),
        log: false
      )
end
