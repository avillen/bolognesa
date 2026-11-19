defmodule Bolognesa.Series.Application.Ports.Readers.WatchedEntriesReader do
  @moduledoc "File-independent watched reads and resolution of the current played file's season entries."
  alias Bolognesa.Series.Domain.ReadModels.ContinueEntry
  alias Bolognesa.Series.Domain.ReadModels.Episode
  alias Bolognesa.Series.Domain.ReadModels.Season
  alias Bolognesa.Series.Domain.ReadModels.Series
  alias Bolognesa.Series.Domain.ReadModels.WatchedEntry
  alias Bolognesa.Series.Domain.ValueObjects.SeasonEntry

  @type adapter :: module()
  @type scope ::
          {:episode, Episode.id()}
          | {:season, Season.id()}
          | {:series, Series.id()}

  @doc "List account-watched entries bounded by one episode, season or series, ordered by episode ID then part (nil first)."
  @callback list_watched_entries(user_id :: pos_integer(), scope()) ::
              {:ok, [WatchedEntry.t()]} | {:error, :unavailable}

  @doc "List a series' regular entries (season 0 excluded) by season, episode and part (nil first), with the account's watched date."
  @callback list_continue_entries(user_id :: pos_integer(), Series.id()) ::
              {:ok, [ContinueEntry.t()]} | {:error, :unavailable}

  @doc "Resolve a confirmed available file associated with the episode, including all parts for whole files."
  @callback fetch_played_entries(Episode.id(), file_id :: pos_integer()) ::
              {:ok, [SeasonEntry.t()]} | :not_found | {:error, :unavailable}
end
