defmodule Bolognesa.Catalog.Application.Ports.Readers.SeriesReader do
  @moduledoc "Catalog-owned reads for series hierarchy and episode versions."
  alias Bolognesa.Catalog.Domain.{Episode, EpisodeVersion, Season, Series}
  @type adapter :: atom()
  @type page_number :: pos_integer()
  @callback list_series(query :: binary(), page :: page_number()) ::
              {:ok, {[{Series.t(), Episode.count(), Episode.count()}], Series.count()}}
              | {:error, :unavailable}
  @callback get_series(series_id :: Series.id()) ::
              {:ok, {Series.t(), [{Season.t(), Episode.count()}]}}
              | {:error, :not_found | :unavailable}
  @callback list_episodes(season_id :: Season.id(), page :: page_number()) ::
              {:ok,
               {Season.t(), Series.t(),
                [{Episode.t(), EpisodeVersion.count(), EpisodeVersion.count()}], Episode.count()}}
              | {:error, :not_found | :unavailable}
  @callback get_episode(episode_id :: Episode.id()) ::
              {:ok, {Episode.t(), Season.t(), Series.t(), [EpisodeVersion.t()]}}
              | {:error, :not_found | :unavailable}
end
