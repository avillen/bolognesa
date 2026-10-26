defmodule Bolognesa.Series.Application.Ports.Readers.SeriesReader do
  @moduledoc "Catalog-owned reads for series hierarchy and episode versions."
  alias Bolognesa.Series.Domain.ReadModels.Episode
  alias Bolognesa.Series.Domain.ReadModels.EpisodeVersion
  alias Bolognesa.Series.Domain.ReadModels.Season
  alias Bolognesa.Series.Domain.ReadModels.Series

  @type adapter :: module()
  @type library_id :: pos_integer() | nil
  @type page_number :: pos_integer()

  @callback list_series(query :: String.t(), page :: page_number(), library_id :: library_id()) ::
              {:ok, {[{Series.t(), Episode.count(), Episode.count()}], Series.count()}}
              | {:error, :unavailable}

  @doc "At most 100 seasons, ordered by number then ID; larger collections return an error."
  @callback fetch_series(Series.id()) ::
              {:ok, {Series.t(), [{Season.t(), Episode.count()}]}}
              | :not_found
              | {:error, :unavailable | :too_many_seasons}

  @callback list_episodes(Season.id(), page :: page_number()) ::
              {:ok,
               {Season.t(), Series.t(),
                [
                  {Episode.t(), pos_integer() | nil, EpisodeVersion.count(),
                   EpisodeVersion.count()}
                ], Episode.count()}}
              | {:error, :not_found | :unavailable}

  @doc "At most 100 versions by file ID, plus adjacent targets in same-season episode/part order."
  @callback fetch_episode(Episode.id()) ::
              {:ok,
               {Episode.t(), Season.t(), Series.t(), [EpisodeVersion.t()],
                {Bolognesa.Series.Domain.ReadModels.EpisodeTarget.t() | nil,
                 Bolognesa.Series.Domain.ReadModels.EpisodeTarget.t() | nil}}}
              | :not_found
              | {:error, :unavailable | :too_many_versions}
  @callback fetch_next_playable_episode(Episode.id(), pos_integer()) ::
              {:ok, Bolognesa.Series.Domain.ReadModels.EpisodeTarget.t()}
              | :not_found
              | {:error, :unavailable | :part_unavailable}

  @doc "Next available episode in season/episode order, after all episodes in the completed file."
  @callback fetch_next_available_episode(Episode.id(), file_id :: pos_integer()) ::
              {:ok, Episode.t()} | :not_found | {:error, :unavailable}
end
