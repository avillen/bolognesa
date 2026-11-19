defmodule Bolognesa.Series.Application.UseCases.MarkWatchedEntries do
  @moduledoc "Mark one known season entry, or every known entry of a season, as watched now."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Series.Application.Ports.Readers.WatchedEntriesReader
  alias Bolognesa.Series.Application.Ports.Repositories.WatchedEntriesRepository
  alias Bolognesa.Series.Domain.ReadModels.Season
  alias Bolognesa.Series.Domain.ValueObjects.SeasonEntry

  @type scope :: {:entry, SeasonEntry.t()} | {:season, Season.id()}
  @type result :: :ok | {:error, :forbidden | :not_found | :unavailable}
  @spec call(
          AuthenticatedUser.t() | nil,
          scope(),
          WatchedEntriesReader.adapter(),
          WatchedEntriesRepository.adapter()
        ) :: result()
  def call(actor, scope, reader, repository) do
    with :ok <- Accounts.authorize(actor, :admin),
         {:ok, entries} <- resolve(scope, reader) do
      repository.upsert(actor.id, entries, DateTime.utc_now())
    end
  end

  defp resolve({:entry, entry}, reader) do
    with {:ok, entries} <- reader.list_season_entries({:episode, entry.episode_id}) do
      if entry in entries, do: {:ok, [entry]}, else: {:error, :not_found}
    end
  end

  defp resolve({:season, id}, reader) do
    case reader.list_season_entries({:season, id}) do
      {:ok, []} -> {:error, :not_found}
      result -> result
    end
  end
end
