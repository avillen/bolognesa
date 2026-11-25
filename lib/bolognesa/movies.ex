defmodule Bolognesa.Movies do
  @moduledoc "Owns movie browsing, identification, corrections, recovery, and watched state."
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Movies.Application.Ports.Providers.MovieProvider
  alias Bolognesa.Movies.Application.UseCases.CorrectMovieIdentification
  alias Bolognesa.Movies.Application.UseCases.GetMovie
  alias Bolognesa.Movies.Application.UseCases.GetMovie.Response, as: MovieDetail
  alias Bolognesa.Movies.Application.UseCases.ListMovieReviewItems
  alias Bolognesa.Movies.Application.UseCases.ListMovieReviewItems.Response, as: MovieReviewPage
  alias Bolognesa.Movies.Application.UseCases.ListMovies
  alias Bolognesa.Movies.Application.UseCases.ListMovies.Response, as: MoviePage
  alias Bolognesa.Movies.Application.UseCases.MarkWatchedMovie
  alias Bolognesa.Movies.Application.UseCases.RecordWatchedMovie
  alias Bolognesa.Movies.Application.UseCases.RetryIdentification
  alias Bolognesa.Movies.Application.UseCases.SearchMovieCandidates
  alias Bolognesa.Movies.Application.UseCases.UnmarkWatchedMovie
  alias Bolognesa.Movies.Domain.Entities.Identification
  alias Bolognesa.Movies.Domain.ReadModels.Movie
  alias Bolognesa.Movies.Infrastructure.Providers.TmdbMovieProvider
  alias Bolognesa.Movies.Infrastructure.Readers.EctoMovieReviewReader
  alias Bolognesa.Movies.Infrastructure.Readers.EctoMoviesReader
  alias Bolognesa.Movies.Infrastructure.Readers.EctoWatchedMoviesReader
  alias Bolognesa.Movies.Infrastructure.Repositories.EctoIdentificationRepository
  alias Bolognesa.Movies.Infrastructure.Repositories.EctoWatchedMoviesRepository

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
          | :too_many_versions
          | :unusable_name
          | MovieProvider.reason()
  @type transaction_repository :: atom()
  @type request_entry :: %{
          required(:file_id) => pos_integer(),
          required(:revision) => pos_integer(),
          required(:requested?) => boolean()
        }

  @spec list_movies(AuthenticatedUser.t(), String.t(), pos_integer(), pos_integer() | nil) ::
          {:ok, MoviePage.t()} | {:error, reason()}
  def list_movies(actor, query, page, library_id \\ nil),
    do: ListMovies.call(actor, query, page, EctoMoviesReader, library_id)

  @doc "Read a movie with its versions and the account's latest watched date, if any."
  @spec get_movie(AuthenticatedUser.t(), Movie.id()) ::
          {:ok, MovieDetail.t()} | {:error, reason()}
  def get_movie(actor, id),
    do: GetMovie.call(actor, id, EctoMoviesReader, EctoWatchedMoviesReader)

  @doc "Record a client-qualified playback; the caller must correlate and deduplicate the current attempt."
  @spec record_watched(AuthenticatedUser.t() | nil, Movie.id(), pos_integer()) ::
          RecordWatchedMovie.result()
  def record_watched(actor, movie_id, file_id),
    do:
      RecordWatchedMovie.call(
        actor,
        movie_id,
        file_id,
        EctoWatchedMoviesReader,
        EctoWatchedMoviesRepository
      )

  @doc "Mark a catalog movie as watched now."
  @spec mark_watched(AuthenticatedUser.t() | nil, Movie.id()) :: MarkWatchedMovie.result()
  def mark_watched(actor, movie_id),
    do:
      MarkWatchedMovie.call(actor, movie_id, EctoWatchedMoviesReader, EctoWatchedMoviesRepository)

  @doc "Remove a movie from this account's watched movies."
  @spec unmark_watched(AuthenticatedUser.t() | nil, Movie.id()) ::
          :ok | {:error, :forbidden | :unavailable}
  def unmark_watched(actor, movie_id),
    do: UnmarkWatchedMovie.call(actor, movie_id, EctoWatchedMoviesRepository)

  @spec list_review_items(AuthenticatedUser.t(), pos_integer()) ::
          {:ok, MovieReviewPage.t()} | {:error, reason()}
  def list_review_items(actor, page),
    do: ListMovieReviewItems.call(actor, page, EctoMovieReviewReader)

  @spec search_candidates(AuthenticatedUser.t(), String.t()) ::
          {:ok, [Bolognesa.Movies.Domain.ValueObjects.MovieCandidate.t()]} | {:error, reason()}
  def search_candidates(actor, query), do: SearchMovieCandidates.call(actor, query, provider())

  @spec correct(AuthenticatedUser.t(), pos_integer(), :unidentified | {:tmdb, pos_integer()}) ::
          {:ok, Identification.t()} | {:error, reason()}
  def correct(actor, id, choice),
    do:
      CorrectMovieIdentification.call(actor, id, choice, EctoIdentificationRepository, provider())

  @spec retry(AuthenticatedUser.t(), pos_integer()) ::
          {:ok, Identification.t()} | {:error, reason()}
  def retry(actor, id), do: RetryIdentification.call(actor, id, EctoIdentificationRepository)

  @spec request_batch_in_transaction!(
          transaction_repository(),
          [request_entry()]
        ) :: non_neg_integer()
  def request_batch_in_transaction!(repo, entries),
    do: EctoIdentificationRepository.request_batch!(repo, entries)

  defp provider, do: Application.get_env(:bolognesa, :movie_provider_adapter, TmdbMovieProvider)
end
