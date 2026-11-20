defmodule Bolognesa.Series.Application.UseCases.FetchEpisode do
  @moduledoc "Authorize an episode detail, its physical versions and the entries of its season."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.ReadQuery
  alias Bolognesa.Series.Application.Ports.Readers.SeriesReader
  alias Bolognesa.Series.Application.Ports.Readers.WatchedEntriesReader
  alias Bolognesa.Series.Application.UseCases.FetchEpisode.Response, as: EpisodeDetail
  alias Bolognesa.Series.Domain.ReadModels.Episode

  @spec call(
          AuthenticatedUser.t(),
          Episode.id(),
          SeriesReader.adapter(),
          WatchedEntriesReader.adapter()
        ) ::
          {:ok, EpisodeDetail.t()}
          | {:error, :forbidden | :not_found | :unavailable | :too_many_versions}
  def call(actor, id, series_reader, watched_reader) do
    with :ok <- Accounts.authorize(actor, :admin),
         :ok <- ReadQuery.validate_id(id),
         {:ok, {_episode, season, _series, _versions} = result} <- series_reader.fetch_episode(id),
         {:ok, entries} <- watched_reader.list_entries(actor.id, {:season, season.id}) do
      {:ok, EpisodeDetail.from_domain(result, entries)}
    end
  end
end
