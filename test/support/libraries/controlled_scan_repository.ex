defmodule Bolognesa.Libraries.Support.ControlledScanRepository do
  @moduledoc false
  @behaviour Bolognesa.Libraries.Application.Ports.Repositories.ScanRepository
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoScanRepository

  @impl true
  defdelegate request(id), to: EctoScanRepository
  @impl true
  defdelegate request(id, force_inspection?), to: EctoScanRepository
  @impl true
  defdelegate status(id), to: EctoScanRepository
  @impl true
  defdelegate begin_attempt(id, attempt), to: EctoScanRepository
  @impl true
  defdelegate save_batch(id, generation, entries), to: EctoScanRepository
  @impl true
  defdelegate complete(id, generation), to: EctoScanRepository
  @impl true
  defdelegate fail(id, generation, reason, state), to: EctoScanRepository
  @impl true
  def reconcile_jobs(now) do
    send(Process.whereis(:scan_reconciliation_owner), {:reconciliation, self(), now})

    receive do
      {:reconciled, result} -> result
    end
  end
end
