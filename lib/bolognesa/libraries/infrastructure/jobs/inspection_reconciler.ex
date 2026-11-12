defmodule Bolognesa.Libraries.Infrastructure.Jobs.InspectionReconciler do
  @moduledoc "Resolves technical inspections left unfinished by terminal or lost jobs."
  alias Bolognesa.Infrastructure.Jobs.PeriodicRunner
  alias Bolognesa.Infrastructure.Observability.Events

  alias Bolognesa.Libraries.Application.Ports.Repositories.InspectionRepository
  alias Bolognesa.Libraries.Application.Ports.Services.LibraryStatusNotifier
  alias Bolognesa.Libraries.Application.UseCases.ReconcileInspections
  alias Bolognesa.Libraries.Infrastructure.Jobs.InspectionPolicy
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoInspectionRepository
  alias Bolognesa.Libraries.Infrastructure.Services.LibraryStatusNotifications

  @type option ::
          {:repository, InspectionRepository.adapter()}
          | {:notifications, LibraryStatusNotifier.adapter()}
          | {:interval_ms, pos_integer()}
          | {:name, GenServer.name()}

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    repository = Keyword.get(opts, :repository, EctoInspectionRepository)
    notifications = Keyword.get(opts, :notifications, LibraryStatusNotifications)

    PeriodicRunner.start_link(
      name: Keyword.get(opts, :name, __MODULE__),
      interval_ms: Keyword.get(opts, :interval_ms, InspectionPolicy.reconcile_interval_ms()),
      run: fn -> run(repository, notifications) end
    )
  end

  @spec child_spec([option()]) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}
  end

  defp run(repository, notifications) do
    ReconcileInspections.call(DateTime.utc_now(), repository, notifications)
  rescue
    _exception ->
      Events.emit(:libraries, :reconciliation, :failed, %{
        operation: :inspection,
        reason: :unexpected_failure
      })
  catch
    _kind, _value ->
      Events.emit(:libraries, :reconciliation, :failed, %{
        operation: :inspection,
        reason: :unexpected_failure
      })
  end
end
