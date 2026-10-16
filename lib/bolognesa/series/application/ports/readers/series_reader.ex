defmodule Bolognesa.Series.Application.Ports.Readers.SeriesReader do
  @moduledoc "Catalog-owned reads for series hierarchy and episode versions."
  alias Bolognesa.Series.Domain.ReadModels.Episode
  alias Bolognesa.Series.Domain.ReadModels.EpisodeVersion
  alias Bolognesa.Series.Domain.ReadModels.Season
  alias Bolognesa.Series.Domain.ReadModels.Series

  @type adapter :: atom()
  @type library_id :: pos_integer() | nil
  @type page_number :: pos_integer()

  @callback list_series(query :: String.t(), page :: page_number(), library_id :: library_id()) ::
              {:ok, {[{Series.t(), Episode.count(), Episode.count()}], Series.count()}}
              | {:error, :unavailable}

  @callback get_series(Series.id()) ::
              {:ok, {Series.t(), [{Season.t(), Episode.count()}]}}
              | {:error, :not_found | :unavailable}

  @callback list_episodes(Season.id(), page :: page_number()) ::
              {:ok,
               {Season.t(), Series.t(),
                [{Episode.t(), EpisodeVersion.count(), EpisodeVersion.count()}], Episode.count()}}
              | {:error, :not_found | :unavailable}

  @callback get_episode(Episode.id()) ::
              {:ok, {Episode.t(), Season.t(), Series.t(), [EpisodeVersion.t()]}}
              | {:error, :not_found | :unavailable}
end
