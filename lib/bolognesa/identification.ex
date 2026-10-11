defmodule Bolognesa.Identification do
  @moduledoc "Public identification and manual correction API."

  alias Bolognesa.Identification.Application.Dto.ReviewPage
  alias Bolognesa.Identification.Application.Dto.SeriesReviewItem
  alias Bolognesa.Identification.Application.Dto.SeriesReviewPage
  alias Bolognesa.Identification.Application.Ports.Providers.SeriesProvider
  alias Bolognesa.Identification.Application.UseCases.CorrectIdentification
  alias Bolognesa.Identification.Application.UseCases.CorrectSeriesIdentification
  alias Bolognesa.Identification.Application.UseCases.GetSeriesReviewItem
  alias Bolognesa.Identification.Application.UseCases.GetSeriesSeason
  alias Bolognesa.Identification.Application.UseCases.ListReviewItems
  alias Bolognesa.Identification.Application.UseCases.ListSeriesReviewItems
  alias Bolognesa.Identification.Application.UseCases.RetryIdentification
  alias Bolognesa.Identification.Application.UseCases.SearchCandidates
  alias Bolognesa.Identification.Application.UseCases.SearchSeriesCandidates
  alias Bolognesa.Identification.Domain.Identification, as: IdentificationDecision
  alias Bolognesa.Identification.Domain.SeasonDetails
  alias Bolognesa.Identification.Domain.SeriesCandidate
  alias Bolognesa.Identification.Infrastructure.Providers.TmdbMovieProvider
  alias Bolognesa.Identification.Infrastructure.Providers.TmdbSeriesProvider
  alias Bolognesa.Identification.Infrastructure.Readers.EctoReviewReader
  alias Bolognesa.Identification.Infrastructure.Readers.EctoSeriesReviewReader
  alias Bolognesa.Identification.Infrastructure.Repositories.EctoIdentificationRepository
  alias Bolognesa.Identification.Infrastructure.Repositories.EctoRequestWriter
  alias Bolognesa.Identity.Domain.Actor

  @spec get_series_review_item(Actor.t(), pos_integer()) ::
          {:ok, SeriesReviewItem.t()} | {:error, :forbidden | :not_found | :unavailable}
  def get_series_review_item(actor, id),
    do: GetSeriesReviewItem.call(actor, id, EctoSeriesReviewReader)

  @spec list_series_review_items(Actor.t(), pos_integer()) ::
          {:ok, SeriesReviewPage.t()} | {:error, :forbidden | :invalid_page | :unavailable}
  def list_series_review_items(actor, page),
    do: ListSeriesReviewItems.call(actor, page, EctoSeriesReviewReader)

  @spec correct_series(Actor.t(), pos_integer(), CorrectSeriesIdentification.choice()) ::
          {:ok, IdentificationDecision.t()} | {:error, CorrectSeriesIdentification.reason()}
  def correct_series(actor, file_id, choice),
    do:
      CorrectSeriesIdentification.call(
        actor,
        file_id,
        choice,
        EctoIdentificationRepository,
        series_provider()
      )

  @spec search_series_candidates(Actor.t(), binary()) ::
          {:ok, [SeriesCandidate.t()]}
          | {:error, :forbidden | :invalid_query | SeriesProvider.reason()}
  def search_series_candidates(actor, query),
    do: SearchSeriesCandidates.call(actor, query, series_provider())

  @spec series_season(Actor.t(), pos_integer(), non_neg_integer()) ::
          {:ok, SeasonDetails.t()}
          | {:error, :forbidden | :invalid_selection | SeriesProvider.reason()}
  def series_season(actor, id, number),
    do: GetSeriesSeason.call(actor, id, number, series_provider())

  defp series_provider,
    do: Application.get_env(:bolognesa, :series_provider_adapter, TmdbSeriesProvider)

  @spec correct(Actor.t(), pos_integer(), :unidentified | {:tmdb, pos_integer()}) ::
          {:ok, IdentificationDecision.t()} | {:error, atom()}
  def correct(actor, file_id, choice),
    do:
      CorrectIdentification.call(
        actor,
        file_id,
        choice,
        EctoIdentificationRepository,
        TmdbMovieProvider
      )

  @spec retry(Actor.t(), pos_integer()) ::
          {:ok, IdentificationDecision.t()} | {:error, atom()}
  def retry(actor, file_id),
    do: RetryIdentification.call(actor, file_id, EctoIdentificationRepository)

  @spec list_review_items(Actor.t(), pos_integer()) ::
          {:ok, ReviewPage.t()} | {:error, :forbidden | :invalid_page | :unavailable}
  def list_review_items(actor, page), do: ListReviewItems.call(actor, page, EctoReviewReader)

  @spec search_candidates(Actor.t(), binary()) :: {:ok, list()} | {:error, atom()}
  def search_candidates(actor, query),
    do: SearchCandidates.call(actor, query, TmdbMovieProvider)

  @type request_entry :: %{
          required(:file_id) => pos_integer(),
          required(:revision) => pos_integer(),
          required(:requested?) => boolean()
        }

  @doc "Write identification requests within an existing inventory transaction."
  @spec request_batch_in_transaction!(module(), [request_entry()]) :: non_neg_integer()
  def request_batch_in_transaction!(repo, entries),
    do: EctoRequestWriter.request_batch!(repo, entries)
end
