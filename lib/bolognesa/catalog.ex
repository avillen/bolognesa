defmodule Bolognesa.Catalog do
  @moduledoc "Movie and series catalog queries."
  alias Bolognesa.Catalog.Application.UseCases.{
    GetEpisode,
    GetMovie,
    GetSeries,
    ListEpisodes,
    ListMovies,
    SearchSeries
  }

  alias Bolognesa.Catalog.Application.Dto.{
    EpisodeDetail,
    EpisodePage,
    MovieDetail,
    MoviePage,
    SeriesDetail,
    SeriesPage
  }

  alias Bolognesa.Catalog.Application.Ports.Readers.SeriesReader
  alias Bolognesa.Catalog.Domain.ReadModels.Series.Episode
  alias Bolognesa.Catalog.Domain.ReadModels.Series.Season
  alias Bolognesa.Catalog.Domain.ReadModels.Series.Series
  alias Bolognesa.Catalog.Infrastructure.Readers.{EctoMoviesReader, EctoSeriesReader}
  alias Bolognesa.Identity.Domain.Entities.Actor

  @spec search_series(Actor.t(), binary(), SeriesReader.page_number(), SeriesReader.library_id()) ::
          {:ok, SeriesPage.t()}
          | {:error, :forbidden | :invalid_query | :invalid_page | :unavailable}
  def search_series(actor, query, page, library_id \\ nil),
    do: SearchSeries.call(actor, query, page, EctoSeriesReader, library_id)

  @spec get_series(Actor.t(), Series.id()) ::
          {:ok, SeriesDetail.t()} | {:error, :forbidden | :not_found | :unavailable}
  def get_series(actor, id), do: GetSeries.call(actor, id, EctoSeriesReader)

  @spec list_episodes(Actor.t(), Season.id(), SeriesReader.page_number()) ::
          {:ok, EpisodePage.t()}
          | {:error, :forbidden | :not_found | :invalid_page | :unavailable}
  def list_episodes(actor, id, page), do: ListEpisodes.call(actor, id, page, EctoSeriesReader)

  @spec get_episode(Actor.t(), Episode.id()) ::
          {:ok, EpisodeDetail.t()} | {:error, :forbidden | :not_found | :unavailable}
  def get_episode(actor, id), do: GetEpisode.call(actor, id, EctoSeriesReader)

  @spec list_movies(Actor.t(), binary(), pos_integer(), pos_integer() | nil) ::
          {:ok, MoviePage.t()} | {:error, :forbidden | :invalid_query | :unavailable}
  def list_movies(actor, query, page, library_id \\ nil),
    do: ListMovies.call(actor, query, page, EctoMoviesReader, library_id)

  @spec get_movie(Actor.t(), pos_integer()) ::
          {:ok, MovieDetail.t()} | {:error, :forbidden | :not_found | :unavailable}
  def get_movie(actor, id), do: GetMovie.call(actor, id, EctoMoviesReader)
end
