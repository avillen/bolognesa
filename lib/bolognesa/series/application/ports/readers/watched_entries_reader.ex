defmodule Bolognesa.Series.Application.Ports.Readers.WatchedEntriesReader do
  @moduledoc "File-independent watched reads and resolution of the current played file's season entries."
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

  @doc """
  Return watched entries ordered by episode ID then part (nil first).
  Missing scope or no activity returns an empty list. Includes unavailable and historical
  entries; no inventory join. Continue ordering belongs to its use case, not timestamp
  or ID order here.
  """
  @callback list_watched_entries(user_id :: pos_integer(), scope()) ::
              {:ok, [WatchedEntry.t()]} | {:error, :unavailable}

  @doc "Resolve a confirmed available file associated with the episode, including all parts for whole files."
  @callback list_played_entries(Episode.id(), file_id :: pos_integer()) ::
              {:ok, [SeasonEntry.t()]} | :not_found | {:error, :unavailable}
end
