defmodule Bolognesa.Catalog.Application.ListEpisodes do
  @moduledoc "Authorize a bounded season episode page."
  alias Bolognesa.Catalog.Application.Dto.{EpisodeListItem, EpisodePage}
  alias Bolognesa.Catalog.Application.Ports.SeriesReader
  alias Bolognesa.Catalog.Domain.Season
  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Actor

  @spec call(Actor.t(), Season.id(), SeriesReader.page_number(), SeriesReader.adapter()) ::
          {:ok, EpisodePage.t()}
          | {:error, :forbidden | :not_found | :invalid_page | :unavailable}
  def call(actor, id, page, reader) do
    with :ok <- Identity.authorize(actor, :admin),
         :ok <- valid_id(id),
         :ok <- valid_page(page),
         {:ok, {season, series, rows, total}} <- reader.list_episodes(id, page) do
      {:ok,
       %EpisodePage{
         season: season,
         series: series,
         items: Enum.map(rows, &EpisodeListItem.from_domain/1),
         total: total
       }}
    end
  end

  defp valid_id(id) when is_integer(id) and id > 0, do: :ok
  defp valid_id(_), do: {:error, :not_found}
  defp valid_page(page) when is_integer(page) and page in 1..100_000, do: :ok
  defp valid_page(_), do: {:error, :invalid_page}
end
