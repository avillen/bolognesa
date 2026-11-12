defmodule Bolognesa.Libraries.Infrastructure.Jobs.Reconcilers.ScanReconciler do
  @moduledoc "Reconciles persisted results after startup and after each bounded interval."
  alias Bolognesa.Infrastructure.Jobs.PeriodicRunner
  alias Bolognesa.Infrastructure.Observability.Events

  alias Bolognesa.Libraries.Application.Ports.Repositories.ScanRepository
  alias Bolognesa.Libraries.Application.Ports.Services.LibraryStatusNotifier
  alias Bolognesa.Libraries.Application.UseCases.ReconcileScans
  alias Bolognesa.Libraries.Infrastructure.Jobs.Policies.ScanPolicy
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoScanRepository
  alias Bolognesa.Libraries.Infrastructure.Services.LibraryStatusNotifications

  @type option ::
          {:repository, ScanRepository.adapter()}
          | {:notifications, LibraryStatusNotifier.adapter()}
          | {:interval_ms, pos_integer()}
          | {:name, GenServer.name()}

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    repository = Keyword.get(opts, :repository, EctoScanRepository)
    notifications = Keyword.get(opts, :notifications, LibraryStatusNotifications)

    PeriodicRunner.start_link(
      name: Keyword.get(opts, :name, __MODULE__),
      interval_ms: Keyword.get(opts, :interval_ms, ScanPolicy.reconcile_interval_ms()),
      run: fn -> run(repository, notifications) end
    )
  end

  @spec child_spec([option()]) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}
  end

  defp run(repository, notifications) do
    ReconcileScans.call(DateTime.utc_now(), repository, notifications)
  rescue
    _exception ->
      Events.emit(:libraries, :reconciliation, :failed, %{
        operation: :scan,
        reason: :unexpected_failure
      })
  catch
    _kind, _value ->
      Events.emit(:libraries, :reconciliation, :failed, %{
        operation: :scan,
        reason: :unexpected_failure
      })
  end
end
