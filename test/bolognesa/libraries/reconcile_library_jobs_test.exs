defmodule Bolognesa.Libraries.ReconcileLibraryJobsTest do
  alias Task.Supervisor, as: TaskSupervisor
  use ExUnit.Case, async: false

  alias Bolognesa.Libraries.Application.UseCases.ReconcileLibraryJobs
  alias Bolognesa.Libraries.Domain.ReadModels.ReconciliationResult
  alias Bolognesa.Libraries.Infrastructure.Services.LibraryStatusNotifications
  alias Bolognesa.Libraries.Support.ControlledScanRepository

  setup do
    Process.register(self(), :scan_reconciliation_owner)
    supervisor = start_supervised!(TaskSupervisor)
    :ok = LibraryStatusNotifications.subscribe()
    %{supervisor: supervisor}
  end

  for operation <- [:scan, :inspection] do
    test "#{operation} notifies confirmed changes even after a later failure", %{
      supervisor: supervisor
    } do
      now = ~U[2026-10-12 12:00:00Z]

      task =
        TaskSupervisor.async_nolink(supervisor, fn ->
          ReconcileLibraryJobs.call(
            unquote(operation),
            now,
            ControlledScanRepository,
            LibraryStatusNotifications
          )
        end)

      assert_receive {:reconciliation, pid, ^now}

      send(
        pid,
        {:reconciled,
         struct(ReconciliationResult, changed_library_ids: [17, 17, 23], error: :unavailable)}
      )

      assert {:error, :unavailable} = Task.await(task)
      assert_receive {:library_status_changed, 17}
      assert_receive {:library_status_changed, 23}
      refute_receive {:library_status_changed, _}
    end

    test "#{operation} leaves unchanged libraries silent", %{supervisor: supervisor} do
      now = ~U[2026-10-12 12:00:00Z]

      task =
        TaskSupervisor.async_nolink(supervisor, fn ->
          ReconcileLibraryJobs.call(
            unquote(operation),
            now,
            ControlledScanRepository,
            LibraryStatusNotifications
          )
        end)

      assert_receive {:reconciliation, pid, ^now}
      send(pid, {:reconciled, struct(ReconciliationResult)})
      assert :ok = Task.await(task)
      refute_receive {:library_status_changed, _}
    end
  end
end
