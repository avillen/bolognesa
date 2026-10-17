defmodule Bolognesa.Libraries.Application.UseCases.DiscoverFiles do
  @moduledoc "Executes a complete walk under a fresh, persisted generation."

  require Logger

  alias Bolognesa.Libraries.Application.Ports.Repositories.ScanRepository
  alias Bolognesa.Libraries.Application.Ports.Services.{FileDiscovery, LibraryStatusNotifier}
  alias Bolognesa.Libraries.Domain.Entities.Scan
  alias Bolognesa.Libraries.Domain.ValueObjects.Files.DiscoveryRequest

  @type result :: :ok | {:cancel, Scan.reason()} | {:error, Scan.reason()}

  @spec call(
          Scan.id(),
          pos_integer(),
          ScanRepository.adapter(),
          FileDiscovery.adapter(),
          LibraryStatusNotifier.adapter()
        ) ::
          result()
  def call(scan_id, attempt, repository, discovery, notifications) do
    case repository.begin_attempt(scan_id, attempt) do
      {:ok, :terminal} -> :ok
      {:ok, scan, library} -> run(scan, library, repository, discovery, notifications)
      {:error, :not_found} -> {:cancel, :unexpected_failure}
      {:error, :unavailable} -> {:error, :storage_unavailable}
    end
  end

  defp run(scan, library, repository, discovery, notifications) do
    notifications.notify(scan.library_id)
    started = System.monotonic_time(:millisecond)
    Logger.info("Library scan started", metadata(scan))
    discover(scan, DiscoveryRequest.new(library), repository, discovery, notifications, started)
  end

  defp discover(
         scan,
         request_result,
         repository,
         discovery,
         notifications,
         started
       ) do
    with {:ok, request} <- request_result,
         :ok <- discovery.walk(request, &save_batch(scan, &1, repository, notifications)),
         {:ok, completed} <- repository.complete(scan.id, scan.generation) do
      notifications.notify(completed.library_id)
      Logger.info("Library scan completed", result_metadata(completed, started))
      :ok
    else
      {:error, :stale_attempt} -> :ok
      {:error, reason} -> record_failure(scan, reason, repository, notifications, started)
    end
  end

  defp save_batch(scan, entries, repository, notifications) do
    case repository.save_batch(scan.id, scan.generation, entries) do
      {:ok, saved} -> notifications.notify(saved.library_id)
      {:error, _reason} = error -> error
    end
  end

  defp record_failure(scan, error, repository, notifications, started) do
    {state, result, reason} = classify(error)

    case repository.fail(scan.id, scan.generation, reason, state) do
      :ok ->
        notifications.notify(scan.library_id)
        log_failure(result, reason, failure_metadata(scan, repository, started))
        {result, reason}

      {:error, :stale_attempt} ->
        :ok

      {:error, :unavailable} ->
        {:error, :storage_unavailable}
    end
  end

  defp metadata(scan),
    do: [
      library_id: scan.library_id,
      scan_id: scan.id,
      job_id: scan.job_id,
      attempt: scan.attempt
    ]

  defp result_metadata(scan, started),
    do: metadata(scan) ++ [files_discovered: scan.files_discovered, duration_ms: elapsed(started)]

  defp failure_metadata(scan, repository, started) do
    case repository.fetch_status(scan.library_id) do
      {:ok, %{latest_scan: %{id: id} = latest}} when id == scan.id ->
        result_metadata(latest, started)

      _ ->
        metadata(scan) ++ [duration_ms: elapsed(started)]
    end
  rescue
    _ -> metadata(scan) ++ [duration_ms: elapsed(started)]
  catch
    _, _ -> metadata(scan) ++ [duration_ms: elapsed(started)]
  end

  defp elapsed(started), do: max(System.monotonic_time(:millisecond) - started, 0)

  defp log_failure(:cancel, reason, metadata),
    do: Logger.error("Library scan failed", [reason: reason] ++ metadata)

  defp log_failure(:error, reason, metadata),
    do: Logger.warning("Library scan execution failed", [reason: reason] ++ metadata)

  defp classify(:unavailable), do: {:retrying, :error, :storage_unavailable}
  defp classify(reason), do: {:failed, :cancel, reason}
end
