defmodule Bolognesa.Libraries.Application.UseCases.DiscoverFiles do
  @moduledoc "Executes a complete walk under a fresh, persisted generation."

  alias Bolognesa.Infrastructure.Observability.Events

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
          LibraryStatusNotifier.adapter(),
          integer() | nil
        ) ::
          result()
  def call(scan_id, attempt, repository, discovery, notifications, job_id \\ nil) do
    metadata = %{scan_id: scan_id, attempt: attempt, job_id: job_id}

    case repository.begin_attempt(scan_id, attempt) do
      {:ok, :terminal} ->
        Events.emit(:libraries, :scan, :stale, Map.put(metadata, :reason, :terminal))
        :ok

      {:ok, scan, library} ->
        run(
          %{scan | job_id: job_id || scan.job_id},
          library,
          repository,
          discovery,
          notifications
        )

      {:error, :not_found} ->
        Events.emit(:libraries, :scan, :rejected, Map.put(metadata, :reason, :not_found))
        {:cancel, :unexpected_failure}

      {:error, :unavailable} ->
        Events.emit(
          :libraries,
          :scan,
          :retryable,
          Map.put(metadata, :reason, :storage_unavailable)
        )

        {:error, :storage_unavailable}
    end
  end

  defp run(scan, library, repository, discovery, notifications) do
    notifications.notify(scan.library_id)
    started = Events.started_at()
    Events.emit(:libraries, :scan, :started, metadata(scan))
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
      observe(:completed, completed, started)
      :ok
    else
      {:error, :stale_attempt} ->
        observe(:stale, scan, started, :stale_attempt)
        :ok

      {:error, reason} ->
        record_failure(scan, reason, repository, notifications, started)
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
        observe(if(result == :cancel, do: :failed, else: :retryable), scan, started, reason)
        {result, reason}

      {:error, :stale_attempt} ->
        observe(:stale, scan, started, :stale_attempt)
        :ok

      {:error, :unavailable} ->
        observe(:retryable, scan, started, :storage_unavailable)
        {:error, :storage_unavailable}
    end
  end

  defp metadata(scan),
    do: %{
      library_id: scan.library_id,
      scan_id: scan.id,
      job_id: scan.job_id,
      attempt: scan.attempt
    }

  defp observe(outcome, scan, started, reason \\ nil) do
    metadata = if reason, do: Map.put(metadata(scan), :reason, reason), else: metadata(scan)

    measurements = %{duration_ms: Events.elapsed(started)}

    measurements =
      if outcome == :completed,
        do: Map.put(measurements, :files_discovered, scan.files_discovered),
        else: measurements

    Events.emit(:libraries, :scan, outcome, metadata, measurements)
  end

  defp classify(:unavailable), do: {:retrying, :error, :storage_unavailable}
  defp classify(reason), do: {:failed, :cancel, reason}
end
