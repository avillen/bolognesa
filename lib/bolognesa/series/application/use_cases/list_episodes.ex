defmodule Bolognesa.Series.Application.UseCases.ListEpisodes do
  @moduledoc "Authorize a bounded season episode page."
  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Entities.Actor
  alias Bolognesa.Series.Application.Ports.Readers.SeriesReader
  alias Bolognesa.Series.Application.UseCases.ListEpisodes.Response, as: EpisodePage
  alias Bolognesa.Series.Domain.ReadModels.Season

  @spec call(Actor.t(), Season.id(), SeriesReader.page_number(), SeriesReader.adapter()) ::
          {:ok, EpisodePage.t()}
          | {:error, :forbidden | :not_found | :invalid_page | :unavailable}
  def call(actor, id, page, reader) do
    with :ok <- Identity.authorize(actor, :admin),
         :ok <- valid_id(id),
         :ok <- valid_page(page),
         {:ok, result} <- reader.list_episodes(id, page) do
      {:ok, EpisodePage.from_domain(result)}
    end
  end

  defp valid_id(id) when is_integer(id) and id > 0, do: :ok
  defp valid_id(_), do: {:error, :not_found}
  defp valid_page(page) when is_integer(page) and page in 1..100_000, do: :ok
  defp valid_page(_), do: {:error, :invalid_page}
end
