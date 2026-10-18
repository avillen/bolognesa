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
                [{Episode.t(), EpisodeVersion.count(), EpisodeVersion.count()}], Episode.count()}}
              | {:error, :not_found | :unavailable}

  @doc "At most 100 versions, ordered by file ID; larger collections return an error."
  @callback fetch_episode(Episode.id()) ::
              {:ok, {Episode.t(), Season.t(), Series.t(), [EpisodeVersion.t()]}}
              | :not_found
              | {:error, :unavailable | :too_many_versions}
end
