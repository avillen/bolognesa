defmodule Bolognesa.Libraries.Support.UnavailableScanRepository do
  @moduledoc false
  @behaviour Bolognesa.Libraries.Application.Ports.Repositories.ScanRepository
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoScanRepository

  @impl true
  defdelegate request(id), to: EctoScanRepository
  @impl true
  defdelegate request(id, force_inspection?), to: EctoScanRepository
  @impl true
  defdelegate fetch_status(id), to: EctoScanRepository
  @impl true
  defdelegate begin_attempt(id, attempt), to: EctoScanRepository
  @impl true
  def save_batch(_id, _generation, _entries), do: {:error, :unavailable}
  @impl true
  defdelegate complete(id, generation), to: EctoScanRepository
  @impl true
  defdelegate fail(id, generation, reason, state), to: EctoScanRepository
  @impl true
  defdelegate reconcile_jobs(now), to: EctoScanRepository
end
