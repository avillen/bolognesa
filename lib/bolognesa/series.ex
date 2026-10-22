defmodule Bolognesa.Series do
  @moduledoc "Owns series browsing, identification, corrections, and recovery."
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Series.Application.Dto.SeriesReviewItem
  alias Bolognesa.Series.Application.Ports.Providers.SeriesProvider
  alias Bolognesa.Series.Application.UseCases.CorrectSeriesIdentification
  alias Bolognesa.Series.Application.UseCases.FetchEpisode
  alias Bolognesa.Series.Application.UseCases.FetchEpisode.Response, as: EpisodeDetail
  alias Bolognesa.Series.Application.UseCases.FetchNextAvailableEpisode
  alias Bolognesa.Series.Application.UseCases.FetchSeries
  alias Bolognesa.Series.Application.UseCases.FetchSeries.Response, as: SeriesDetail
  alias Bolognesa.Series.Application.UseCases.FetchSeriesReviewItem
  alias Bolognesa.Series.Application.UseCases.FetchSeriesSeason
  alias Bolognesa.Series.Application.UseCases.IdentifySeriesFile
  alias Bolognesa.Series.Application.UseCases.ListEpisodes
  alias Bolognesa.Series.Application.UseCases.ListEpisodes.Response, as: EpisodePage
  alias Bolognesa.Series.Application.UseCases.ListSeriesReviewItems
  alias Bolognesa.Series.Application.UseCases.ListSeriesReviewItems.Response, as: SeriesReviewPage
  alias Bolognesa.Series.Application.UseCases.RetryIdentification
  alias Bolognesa.Series.Application.UseCases.SearchSeries
  alias Bolognesa.Series.Application.UseCases.SearchSeries.Response, as: SeriesPage
  alias Bolognesa.Series.Application.UseCases.SearchSeriesCandidates
  alias Bolognesa.Series.Domain.Entities.Identification
  alias Bolognesa.Series.Infrastructure.Providers.TmdbSeriesProvider
  alias Bolognesa.Series.Infrastructure.Readers.EctoSeriesReader
  alias Bolognesa.Series.Infrastructure.Readers.EctoSeriesReviewReader
  alias Bolognesa.Series.Infrastructure.Repositories.EctoIdentificationRepository
  alias Bolognesa.Series.Infrastructure.Repositories.EctoRequestWriter

  @type reason ::
          :forbidden
          | :not_found
          | :unavailable
          | :invalid_query
          | :invalid_page
          | :invalid_choice
          | :wrong_content_type
          | :source_changed
          | :manual_locked
          | :invalid_selection
          | :incomplete_episodes
          | :too_many_episodes
          | :invalid_episode_numbers
          | :too_many_seasons
          | :too_many_versions
          | :unusable_name
          | SeriesProvider.reason()
  @type transaction_repository :: atom()
  @type request_entry :: %{
          required(:file_id) => pos_integer(),
          required(:revision) => pos_integer(),
          required(:requested?) => boolean()
        }

  @spec search_series(AuthenticatedUser.t(), String.t(), pos_integer(), pos_integer() | nil) ::
          {:ok, SeriesPage.t()} | {:error, reason()}
  def search_series(actor, query, page, library_id \\ nil),
    do: SearchSeries.call(actor, query, page, EctoSeriesReader, library_id)

  @spec fetch_series(AuthenticatedUser.t(), pos_integer()) ::
          {:ok, SeriesDetail.t()} | :not_found | {:error, reason()}
  def fetch_series(actor, id), do: FetchSeries.call(actor, id, EctoSeriesReader)

  @spec list_episodes(AuthenticatedUser.t(), pos_integer(), pos_integer()) ::
          {:ok, EpisodePage.t()} | {:error, reason()}
  def list_episodes(actor, id, page), do: ListEpisodes.call(actor, id, page, EctoSeriesReader)

  @spec fetch_episode(AuthenticatedUser.t(), pos_integer()) ::
          {:ok, EpisodeDetail.t()} | :not_found | {:error, reason()}
  def fetch_episode(actor, id), do: FetchEpisode.call(actor, id, EctoSeriesReader)

  @spec fetch_next_available_episode(AuthenticatedUser.t(), pos_integer(), pos_integer()) ::
          {:ok, Bolognesa.Series.Domain.ReadModels.Episode.t()} | :not_found | {:error, reason()}
  def fetch_next_available_episode(actor, episode_id, file_id),
    do:
      FetchNextAvailableEpisode.call(
        actor,
        episode_id,
        file_id,
        EctoSeriesReader
      )

  @spec list_review_items(AuthenticatedUser.t(), pos_integer()) ::
          {:ok, SeriesReviewPage.t()} | {:error, reason()}
  def list_review_items(actor, page),
    do: ListSeriesReviewItems.call(actor, page, EctoSeriesReviewReader)

  @spec search_candidates(AuthenticatedUser.t(), String.t()) ::
          {:ok, [Bolognesa.Series.Domain.ValueObjects.SeriesCandidate.t()]} | {:error, reason()}
  def search_candidates(actor, query), do: SearchSeriesCandidates.call(actor, query, provider())

  @spec correct(AuthenticatedUser.t(), pos_integer(), CorrectSeriesIdentification.choice()) ::
          {:ok, Identification.t()} | {:error, reason()}
  def correct(actor, id, choice),
    do:
      CorrectSeriesIdentification.call(
        actor,
        id,
        choice,
        EctoIdentificationRepository,
        provider()
      )

  @spec retry(AuthenticatedUser.t(), pos_integer()) ::
          {:ok, Identification.t()} | {:error, reason()}
  def retry(actor, id), do: RetryIdentification.call(actor, id, EctoIdentificationRepository)

  @spec request_batch_in_transaction!(
          transaction_repository(),
          [request_entry()]
        ) :: non_neg_integer()
  def request_batch_in_transaction!(repo, entries),
    do: EctoRequestWriter.request_batch!(repo, entries)

  @spec identify_file(pos_integer(), Identification.token(), pos_integer(), pos_integer() | nil) ::
          :ok | {:error, reason()}
  def identify_file(id, token, attempt, job_id),
    do:
      IdentifySeriesFile.call(
        id,
        token,
        attempt,
        EctoIdentificationRepository,
        provider(),
        job_id
      )

  @spec fetch_review_item(AuthenticatedUser.t(), pos_integer()) ::
          {:ok, SeriesReviewItem.t()} | :not_found | {:error, reason()}
  def fetch_review_item(actor, id),
    do: FetchSeriesReviewItem.call(actor, id, EctoSeriesReviewReader)

  @spec fetch_series_season(AuthenticatedUser.t(), pos_integer(), non_neg_integer()) ::
          {:ok, Bolognesa.Series.Domain.ValueObjects.SeasonDetails.t()}
          | :not_found
          | {:error, reason()}
  def fetch_series_season(actor, id, number),
    do: FetchSeriesSeason.call(actor, id, number, provider())

  defp provider, do: Application.get_env(:bolognesa, :series_provider_adapter, TmdbSeriesProvider)
end
