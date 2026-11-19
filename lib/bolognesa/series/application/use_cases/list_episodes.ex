defmodule Bolognesa.Series.Application.UseCases.ListEpisodes do
  @moduledoc "Authorize a bounded season episode page."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.ReadQuery
  alias Bolognesa.Series.Application.Ports.Readers.SeriesReader
  alias Bolognesa.Series.Application.Ports.Readers.WatchedEntriesReader
  alias Bolognesa.Series.Application.UseCases.ListEpisodes.Response, as: EpisodePage
  alias Bolognesa.Series.Domain.ReadModels.Season

  @spec call(
          AuthenticatedUser.t(),
          Season.id(),
          SeriesReader.page_number(),
          SeriesReader.adapter(),
          WatchedEntriesReader.adapter()
        ) ::
          {:ok, EpisodePage.t()}
          | {:error, :forbidden | :not_found | :invalid_page | :unavailable}
  def call(actor, id, page, series_reader, watched_reader) do
    with :ok <- Accounts.authorize(actor, :admin),
         :ok <- ReadQuery.validate_id(id),
         :ok <- ReadQuery.validate_page(page),
         {:ok, result} <- series_reader.list_episodes(id, page),
         {:ok, watched} <- watched_reader.list_watched_entries(actor.id, {:season, id}) do
      {:ok, EpisodePage.from_domain(result, watched)}
    end
  end
end
