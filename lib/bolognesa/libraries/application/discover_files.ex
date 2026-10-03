defmodule Bolognesa.Libraries.Application.DiscoverFiles do
  @moduledoc "Executes a complete walk under a fresh, persisted generation."

  alias Bolognesa.Libraries.Application.Ports.{FileDiscovery, ScanRepository}
  alias Bolognesa.Libraries.Domain.Scan

  @type result :: :ok | {:cancel, Scan.reason()} | {:error, Scan.reason()}

  @spec call(Scan.id(), pos_integer(), ScanRepository.adapter(), FileDiscovery.adapter()) ::
          result()
  def call(scan_id, attempt, repository, discovery) do
    case repository.begin_attempt(scan_id, attempt) do
      {:ok, :terminal} -> :ok
      {:ok, scan, library} -> discover(scan, library.path, repository, discovery)
      {:error, :not_found} -> {:cancel, :unexpected_failure}
      {:error, :unavailable} -> {:error, :storage_unavailable}
    end
  end

  defp discover(scan, path, repository, discovery) do
    with :ok <- discovery.walk(path, &save_batch(scan, &1, repository)),
         {:ok, _completed} <- repository.complete(scan.id, scan.generation) do
      :ok
    else
      {:error, :stale_attempt} -> :ok
      {:error, reason} -> record_failure(scan, reason, repository)
    end
  end

  defp save_batch(scan, entries, repository) do
    case repository.save_batch(scan.id, scan.generation, entries) do
      {:ok, _scan} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp record_failure(scan, error, repository) do
    {state, result, reason} = classify(error)

    case repository.fail(scan.id, scan.generation, reason, state) do
      :ok -> {result, reason}
      {:error, :stale_attempt} -> :ok
      {:error, :unavailable} -> {:error, :storage_unavailable}
    end
  end

  defp classify(:unavailable), do: {:retrying, :error, :storage_unavailable}
  defp classify(reason), do: {:failed, :cancel, reason}
end
