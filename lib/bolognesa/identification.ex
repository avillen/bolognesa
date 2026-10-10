defmodule Bolognesa.Identification do
  @moduledoc "Public identification and manual correction API."
  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Identification.Application.CorrectIdentification
  alias Bolognesa.Identification.Application.ListReviewItems
  alias Bolognesa.Identification.Application.RetryIdentification
  alias Bolognesa.Identification.Application.SearchCandidates
  alias Bolognesa.Identification.Domain.Identification, as: IdentificationDecision
  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository
  alias Bolognesa.Identification.Infrastructure.Persistence.EctoReviewReader
  alias Bolognesa.Identification.Infrastructure.TmdbMovieProvider

  @spec correct(Actor.t() | nil, pos_integer(), :unidentified | {:tmdb, pos_integer()}) ::
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

  @spec retry(Actor.t() | nil, pos_integer()) ::
          {:ok, IdentificationDecision.t()} | {:error, atom()}
  def retry(actor, file_id),
    do: RetryIdentification.call(actor, file_id, EctoIdentificationRepository)

  @spec list_review_items(Actor.t() | nil, pos_integer()) :: {:ok, map()} | {:error, atom()}
  def list_review_items(actor, page), do: ListReviewItems.call(actor, page, EctoReviewReader)

  @spec search_candidates(Actor.t() | nil, binary()) :: {:ok, list()} | {:error, atom()}
  def search_candidates(actor, query),
    do: SearchCandidates.call(actor, query, TmdbMovieProvider)
end
