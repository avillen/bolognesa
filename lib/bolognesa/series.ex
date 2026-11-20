defmodule Bolognesa.Series do
  @moduledoc "Owns series browsing, identification, corrections, and recovery."
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Series.Application.Dto.SeriesReviewItem
  alias Bolognesa.Series.Application.Ports.Providers.SeriesProvider
  alias Bolognesa.Series.Application.Ports.Readers.WatchedEntriesReader
  alias Bolognesa.Series.Application.UseCases.CorrectSeriesIdentification
  alias Bolognesa.Series.Application.UseCases.FetchContinueTarget
  alias Bolognesa.Series.Application.UseCases.FetchEpisode
  alias Bolognesa.Series.Application.UseCases.FetchEpisode.Response, as: EpisodeDetail
  alias Bolognesa.Series.Application.UseCases.FetchNextPlayableEpisode
  alias Bolognesa.Series.Application.UseCases.FetchSeries
  alias Bolognesa.Series.Application.UseCases.FetchSeries.Response, as: SeriesDetail
  alias Bolognesa.Series.Application.UseCases.FetchSeriesReviewItem
  alias Bolognesa.Series.Application.UseCases.FetchSeriesSeason
  alias Bolognesa.Series.Application.UseCases.ListEpisodes
  alias Bolognesa.Series.Application.UseCases.ListEpisodes.Response, as: EpisodePage
  alias Bolognesa.Series.Application.UseCases.ListRecentSeries
  alias Bolognesa.Series.Application.UseCases.ListSeriesReviewItems
  alias Bolognesa.Series.Application.UseCases.ListSeriesReviewItems.Response, as: SeriesReviewPage
  alias Bolognesa.Series.Application.UseCases.ListWatchedEntries
  alias Bolognesa.Series.Application.UseCases.MarkWatchedEntries
  alias Bolognesa.Series.Application.UseCases.RecordWatchedEntries
  alias Bolognesa.Series.Application.UseCases.RetryIdentification
  alias Bolognesa.Series.Application.UseCases.SearchSeries
  alias Bolognesa.Series.Application.UseCases.SearchSeries.Response, as: SeriesPage
  alias Bolognesa.Series.Application.UseCases.SearchSeriesCandidates
  alias Bolognesa.Series.Application.UseCases.UnmarkWatchedEntry
  alias Bolognesa.Series.Domain.Entities.Identification
  alias Bolognesa.Series.Domain.ReadModels.ContinueTarget
  alias Bolognesa.Series.Domain.ReadModels.EntryStatus
  alias Bolognesa.Series.Domain.ValueObjects.Entry
  alias Bolognesa.Series.Infrastructure.Providers.TmdbSeriesProvider
  alias Bolognesa.Series.Infrastructure.Readers.EctoSeriesReader
  alias Bolognesa.Series.Infrastructure.Readers.EctoSeriesReviewReader
  alias Bolognesa.Series.Infrastructure.Readers.EctoWatchedEntriesReader
  alias Bolognesa.Series.Infrastructure.Repositories.EctoIdentificationRepository
  alias Bolognesa.Series.Infrastructure.Repositories.EctoWatchedEntriesRepository

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
          | :ambiguous_name
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
          {:ok, SeriesDetail.t()} | {:error, reason()}
  def fetch_series(actor, id), do: FetchSeries.call(actor, id, EctoSeriesReader)

  @spec list_episodes(AuthenticatedUser.t(), pos_integer(), pos_integer()) ::
          {:ok, EpisodePage.t()} | {:error, reason()}
  def list_episodes(actor, id, page),
    do: ListEpisodes.call(actor, id, page, EctoSeriesReader, EctoWatchedEntriesReader)

  @spec fetch_episode(AuthenticatedUser.t(), pos_integer()) ::
          {:ok, EpisodeDetail.t()} | {:error, reason()}
  def fetch_episode(actor, id),
    do: FetchEpisode.call(actor, id, EctoSeriesReader, EctoWatchedEntriesReader)

  @spec fetch_next_playable_episode(AuthenticatedUser.t(), pos_integer(), pos_integer()) ::
          {:ok, EntryStatus.t()}
          | {:error, :forbidden | :not_found | :unavailable | :part_unavailable}
  def fetch_next_playable_episode(actor, episode_id, file_id),
    do:
      FetchNextPlayableEpisode.call(
        actor,
        episode_id,
        file_id,
        EctoWatchedEntriesReader
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
    do: EctoIdentificationRepository.request_batch!(repo, entries)

  @spec fetch_review_item(AuthenticatedUser.t(), pos_integer()) ::
          {:ok, SeriesReviewItem.t()} | {:error, reason()}
  def fetch_review_item(actor, id),
    do: FetchSeriesReviewItem.call(actor, id, EctoSeriesReviewReader)

  @spec fetch_series_season(AuthenticatedUser.t(), pos_integer(), non_neg_integer()) ::
          {:ok, Bolognesa.Series.Domain.ValueObjects.SeasonDetails.t()}
          | {:error, reason()}
  def fetch_series_season(actor, id, number),
    do: FetchSeriesSeason.call(actor, id, number, provider())

  @doc "Read this account's watched entries for an episode, season, or series."
  @spec list_watched_entries(AuthenticatedUser.t() | nil, WatchedEntriesReader.scope()) ::
          {:ok, [EntryStatus.t()]} | {:error, :forbidden | :unavailable}
  def list_watched_entries(actor, scope),
    do: ListWatchedEntries.call(actor, scope, EctoWatchedEntriesReader)

  @doc "Derive this account's Start, Continue or Replay target for a series; nil without regular entries."
  @spec fetch_continue_target(AuthenticatedUser.t() | nil, pos_integer()) ::
          {:ok, ContinueTarget.t() | nil} | {:error, :forbidden | :unavailable}
  def fetch_continue_target(actor, series_id),
    do: FetchContinueTarget.call(actor, series_id, EctoWatchedEntriesReader)

  @doc "Lists up to three recently watched series with their Continue targets within the selected library, or all libraries."
  @spec list_recent_series(AuthenticatedUser.t() | nil, pos_integer() | nil) ::
          ListRecentSeries.result()
  def list_recent_series(actor, library_id),
    do: ListRecentSeries.call(actor, library_id, EctoWatchedEntriesReader)

  @doc "Record a client-qualified playback; the caller must correlate and deduplicate the current attempt."
  @spec record_watched_entries(AuthenticatedUser.t() | nil, pos_integer(), pos_integer()) ::
          RecordWatchedEntries.result()
  def record_watched_entries(actor, episode_id, file_id),
    do:
      RecordWatchedEntries.call(
        actor,
        episode_id,
        file_id,
        EctoWatchedEntriesReader,
        EctoWatchedEntriesRepository
      )

  @doc "Mark a known entry, or every known entry of a season, as watched now."
  @spec mark_entries_watched(AuthenticatedUser.t() | nil, MarkWatchedEntries.scope()) ::
          MarkWatchedEntries.result()
  def mark_entries_watched(actor, scope),
    do:
      MarkWatchedEntries.call(
        actor,
        scope,
        EctoWatchedEntriesReader,
        EctoWatchedEntriesRepository
      )

  @doc "Remove one entry from this account's watched entries."
  @spec unmark_entry_watched(AuthenticatedUser.t() | nil, Entry.t()) ::
          :ok | {:error, :forbidden | :unavailable}
  def unmark_entry_watched(actor, entry),
    do: UnmarkWatchedEntry.call(actor, entry, EctoWatchedEntriesRepository)

  defp provider, do: Application.get_env(:bolognesa, :series_provider_adapter, TmdbSeriesProvider)
end
