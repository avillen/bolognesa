defmodule Bolognesa.Libraries.Application.UseCases.ReconcileInspections do
  @moduledoc "Recovers inspections and notifies changes confirmed before any recovery failure."

  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Libraries.Application.Ports.Repositories.InspectionRepository
  alias Bolognesa.Libraries.Application.Ports.Services.LibraryStatusNotifier

  @type result :: :ok | {:error, :unavailable}

  @spec call(DateTime.t(), InspectionRepository.adapter(), LibraryStatusNotifier.adapter()) ::
          result()
  def call(now, repository, notifications) do
    started = Events.started_at()
    result = repository.reconcile_jobs(now)
    observe(result, started)
    Enum.each(Enum.uniq(result.changed_library_ids), &notifications.notify/1)
    outcome(result.error)
  end

  defp observe(result, started) do
    count = result.changed_library_ids |> Enum.uniq() |> length()
    measurements = %{changed_library_count: count, duration_ms: Events.elapsed(started)}

    if count > 0,
      do:
        Events.emit(
          :libraries,
          :reconciliation,
          :recovered,
          %{operation: :inspection},
          measurements
        )

    if result.error,
      do:
        Events.emit(
          :libraries,
          :reconciliation,
          :retryable,
          %{operation: :inspection, reason: :storage_unavailable},
          measurements
        )

    :ok
  end

  defp outcome(nil), do: :ok
  defp outcome(:unavailable), do: {:error, :unavailable}
end
