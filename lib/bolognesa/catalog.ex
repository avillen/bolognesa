defmodule Bolognesa.Catalog do
  @moduledoc "Movie and series catalog queries."
  alias Bolognesa.Catalog.Application.{
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

  alias Bolognesa.Catalog.Application.Ports.SeriesReader
  alias Bolognesa.Catalog.Domain.{Episode, Season, Series}
  alias Bolognesa.Catalog.Infrastructure.Persistence.{EctoCatalogReader, EctoSeriesReader}
  alias Bolognesa.Identity.Domain.Actor

  @spec search_series(Actor.t(), binary(), SeriesReader.page_number()) ::
          {:ok, SeriesPage.t()}
          | {:error, :forbidden | :invalid_query | :invalid_page | :unavailable}
  def search_series(actor, query, page),
    do: SearchSeries.call(actor, query, page, EctoSeriesReader)

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

  @spec list_movies(Actor.t(), binary(), pos_integer()) ::
          {:ok, MoviePage.t()} | {:error, :forbidden | :invalid_query | :unavailable}
  def list_movies(actor, query, page), do: ListMovies.call(actor, query, page, EctoCatalogReader)

  @spec get_movie(Actor.t(), pos_integer()) ::
          {:ok, MovieDetail.t()} | {:error, :forbidden | :not_found | :unavailable}
  def get_movie(actor, id), do: GetMovie.call(actor, id, EctoCatalogReader)
end
