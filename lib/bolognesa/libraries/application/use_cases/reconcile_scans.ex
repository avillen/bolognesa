defmodule Bolognesa.Libraries.Application.UseCases.ReconcileScans do
  @moduledoc "Recovers scans and notifies changes confirmed before any recovery failure."

  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Libraries.Application.Ports.Repositories.ScanRepository
  alias Bolognesa.Libraries.Application.Ports.Services.LibraryStatusNotifier
  alias Bolognesa.Libraries.Application.Reconciliation

  @type result :: :ok | {:error, :unavailable}

  @spec call(DateTime.t(), ScanRepository.adapter(), LibraryStatusNotifier.adapter()) :: result()
  def call(now, repository, notifications) do
    started = Events.started_at()
    result = repository.reconcile_jobs(now)
    Reconciliation.complete(result, :scan, started, notifications)
  end
end
