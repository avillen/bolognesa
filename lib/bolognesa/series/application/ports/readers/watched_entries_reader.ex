defmodule Bolognesa.Series.Application.Ports.Readers.WatchedEntriesReader do
  @moduledoc "Entries with the account's watched state, and resolution of the current played file's entries."
  alias Bolognesa.Series.Domain.ReadModels.EntryStatus
  alias Bolognesa.Series.Domain.ReadModels.Episode
  alias Bolognesa.Series.Domain.ReadModels.Season
  alias Bolognesa.Series.Domain.ReadModels.Series
  alias Bolognesa.Series.Domain.ValueObjects.Entry

  @type adapter :: module()
  @type scope ::
          {:episode, Episode.id()}
          | {:season, Season.id()}
          | {:series, Series.id()}
          | {:series_of, Episode.id()}

  @doc "List the known entries of an episode, season, series or the series of an episode, including unavailable ones, by season, episode and part (nil first), with the account's watched date."
  @callback list_entries(user_id :: pos_integer(), scope()) ::
              {:ok, [EntryStatus.t()]} | {:error, :unavailable}

  @doc "List up to three series the account watched most recently, newest first, with all their known entries; optionally only series with a confirmed file in the library."
  @callback list_recent_series(user_id :: pos_integer(), library_id :: pos_integer() | nil) ::
              {:ok, [{Series.t(), [EntryStatus.t()]}]} | {:error, :unavailable}

  @doc "Resolve a confirmed available file associated with the episode, including all parts for whole files."
  @callback fetch_played_entries(Episode.id(), file_id :: pos_integer()) ::
              {:ok, [Entry.t()]} | {:error, :not_found | :unavailable}
end
