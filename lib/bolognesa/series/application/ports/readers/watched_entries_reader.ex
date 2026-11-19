defmodule Bolognesa.Series.Application.Ports.Readers.WatchedEntriesReader do
  @moduledoc "Season entries with the account's watched state, and resolution of the current played file's season entries."
  alias Bolognesa.Series.Domain.ReadModels.Episode
  alias Bolognesa.Series.Domain.ReadModels.Season
  alias Bolognesa.Series.Domain.ReadModels.SeasonEntryStatus
  alias Bolognesa.Series.Domain.ReadModels.Series
  alias Bolognesa.Series.Domain.ValueObjects.SeasonEntry

  @type adapter :: module()
  @type scope ::
          {:episode, Episode.id()}
          | {:season, Season.id()}
          | {:series, Series.id()}

  @doc "List the known season entries of an episode, season or series, including unavailable ones, by season, episode and part (nil first), with the account's watched date."
  @callback list_entries(user_id :: pos_integer(), scope()) ::
              {:ok, [SeasonEntryStatus.t()]} | {:error, :unavailable}

  @doc "Resolve a confirmed available file associated with the episode, including all parts for whole files."
  @callback fetch_played_entries(Episode.id(), file_id :: pos_integer()) ::
              {:ok, [SeasonEntry.t()]} | :not_found | {:error, :unavailable}
end
