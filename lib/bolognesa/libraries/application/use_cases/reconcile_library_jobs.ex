defmodule Bolognesa.Libraries.Application.UseCases.ReconcileLibraryJobs do
  @moduledoc "Recovers scans or inspections and notifies changes confirmed before any recovery failure."

  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Libraries.Application.Ports.Repositories.InspectionRepository
  alias Bolognesa.Libraries.Application.Ports.Repositories.ScanRepository
  alias Bolognesa.Libraries.Application.Ports.Services.LibraryStatusNotifier

  @type operation :: :scan | :inspection
  @type result :: :ok | {:error, :unavailable}

  @spec call(
          operation(),
          DateTime.t(),
          ScanRepository.adapter() | InspectionRepository.adapter(),
          LibraryStatusNotifier.adapter()
        ) :: result()
  def call(operation, now, repository, notifications) do
    started = Events.started_at()
    result = repository.reconcile_jobs(now)
    library_ids = Enum.uniq(result.changed_library_ids)

    measurements = %{
      changed_library_count: length(library_ids),
      duration_ms: Events.elapsed(started)
    }

    observe(measurements, operation, result.error)
    Enum.each(library_ids, &notifications.notify/1)
    outcome(result.error)
  end

  defp observe(measurements, operation, error) do
    if measurements.changed_library_count > 0,
      do:
        Events.emit(
          :libraries,
          :reconciliation,
          :recovered,
          %{operation: operation},
          measurements
        )

    if error,
      do:
        Events.emit(
          :libraries,
          :reconciliation,
          :retryable,
          %{operation: operation, reason: :storage_unavailable},
          measurements
        )

    :ok
  end

  defp outcome(nil), do: :ok
  defp outcome(:unavailable), do: {:error, :unavailable}
end
