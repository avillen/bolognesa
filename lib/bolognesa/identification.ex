defmodule Bolognesa.Identification do
  @moduledoc "Public identification and manual correction API."
  alias Bolognesa.Identification.Application.CorrectIdentification
  alias Bolognesa.Identification.Application.Dto.ReviewPage
  alias Bolognesa.Identification.Application.ListReviewItems
  alias Bolognesa.Identification.Application.RetryIdentification
  alias Bolognesa.Identification.Application.SearchCandidates
  alias Bolognesa.Identification.Domain.Identification, as: IdentificationDecision
  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository
  alias Bolognesa.Identification.Infrastructure.Persistence.EctoRequestWriter
  alias Bolognesa.Identification.Infrastructure.Persistence.EctoReviewReader
  alias Bolognesa.Identification.Infrastructure.TmdbMovieProvider
  alias Bolognesa.Identity.Domain.Actor

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
