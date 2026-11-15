defmodule Bolognesa.Libraries.Infrastructure.Jobs.Reconcilers.LibraryJobReconciler do
  @moduledoc "Periodically resolves scans or inspections left unfinished by terminal or lost jobs."
  alias Bolognesa.Infrastructure.Jobs.PeriodicRunner
  alias Bolognesa.Infrastructure.Observability.Events

  alias Bolognesa.Libraries.Application.Ports.Repositories.InspectionRepository
  alias Bolognesa.Libraries.Application.Ports.Repositories.ScanRepository
  alias Bolognesa.Libraries.Application.Ports.Services.LibraryStatusNotifier
  alias Bolognesa.Libraries.Application.UseCases.ReconcileLibraryJobs
  alias Bolognesa.Libraries.Infrastructure.Jobs.Policies.InspectionPolicy
  alias Bolognesa.Libraries.Infrastructure.Jobs.Policies.ScanPolicy
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoInspectionRepository
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoScanRepository
  alias Bolognesa.Libraries.Infrastructure.Services.LibraryStatusNotifications

  @type option ::
          {:operation, ReconcileLibraryJobs.operation()}
          | {:repository, ScanRepository.adapter() | InspectionRepository.adapter()}
          | {:notifications, LibraryStatusNotifier.adapter()}
          | {:interval_ms, pos_integer()}
          | {:name, GenServer.name()}

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    operation = Keyword.fetch!(opts, :operation)
    repository = Keyword.get(opts, :repository, repository(operation))
    notifications = Keyword.get(opts, :notifications, LibraryStatusNotifications)

    PeriodicRunner.start_link(
      name: name(opts),
      interval_ms: Keyword.get(opts, :interval_ms, interval_ms(operation)),
      run: fn -> run(operation, repository, notifications) end
    )
  end

  @spec child_spec([option()]) :: Supervisor.child_spec()
  def child_spec(opts), do: %{id: name(opts), start: {__MODULE__, :start_link, [opts]}}

  defp name(opts),
    do: Keyword.get_lazy(opts, :name, fn -> default_name(Keyword.fetch!(opts, :operation)) end)

  defp default_name(:scan), do: Bolognesa.Libraries.Infrastructure.Jobs.Reconcilers.ScanReconciler

  defp default_name(:inspection),
    do: Bolognesa.Libraries.Infrastructure.Jobs.Reconcilers.InspectionReconciler

  defp repository(:scan), do: EctoScanRepository
  defp repository(:inspection), do: EctoInspectionRepository

  defp interval_ms(:scan), do: ScanPolicy.reconcile_interval_ms()
  defp interval_ms(:inspection), do: InspectionPolicy.reconcile_interval_ms()

  defp run(operation, repository, notifications) do
    ReconcileLibraryJobs.call(operation, DateTime.utc_now(), repository, notifications)
  catch
    _kind, _value -> failed(operation)
  end

  defp failed(operation) do
    Events.emit(:libraries, :reconciliation, :failed, %{
      operation: operation,
      reason: :unexpected_failure
    })
  end
end
