defmodule Bolognesa.Libraries.Application.Reconciliation do
  @moduledoc "Reports and notifies confirmed library changes retained by recovery."

  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Libraries.Application.Ports.Services.LibraryStatusNotifier
  alias Bolognesa.Libraries.Domain.ReadModels.ReconciliationResult

  @type operation :: :scan | :inspection
  @type result :: :ok | {:error, :unavailable}

  @spec complete(
          ReconciliationResult.t(),
          operation(),
          integer(),
          LibraryStatusNotifier.adapter()
        ) ::
          result()
  def complete(result, operation, started, notifications) do
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
