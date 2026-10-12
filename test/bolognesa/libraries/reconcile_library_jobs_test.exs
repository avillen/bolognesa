defmodule Bolognesa.Libraries.ReconcileLibraryJobsTest do
  use ExUnit.Case, async: false

  alias Bolognesa.Libraries.Application.UseCases.{ReconcileInspections, ReconcileScans}
  alias Bolognesa.Libraries.Domain.ReadModels.ReconciliationResult
  alias Bolognesa.Libraries.Infrastructure.Services.LibraryStatusNotifications
  alias Bolognesa.Libraries.Support.ControlledScanRepository

  setup do
    Process.register(self(), :scan_reconciliation_owner)
    supervisor = start_supervised!(Task.Supervisor)
    :ok = LibraryStatusNotifications.subscribe()
    %{supervisor: supervisor}
  end

  for use_case <- [ReconcileScans, ReconcileInspections] do
    test "#{inspect(use_case)} notifies confirmed changes even after a later failure", %{
      supervisor: supervisor
    } do
      now = ~U[2026-10-12 12:00:00Z]

      task =
        Task.Supervisor.async_nolink(supervisor, fn ->
          unquote(use_case).call(now, ControlledScanRepository, LibraryStatusNotifications)
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

    test "#{inspect(use_case)} leaves unchanged libraries silent", %{supervisor: supervisor} do
      now = ~U[2026-10-12 12:00:00Z]

      task =
        Task.Supervisor.async_nolink(supervisor, fn ->
          unquote(use_case).call(now, ControlledScanRepository, LibraryStatusNotifications)
        end)

      assert_receive {:reconciliation, pid, ^now}
      send(pid, {:reconciled, struct(ReconciliationResult)})
      assert :ok = Task.await(task)
      refute_receive {:library_status_changed, _}
    end
  end
end
