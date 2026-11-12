defmodule Bolognesa.Libraries.Infrastructure.Jobs.Oban.ObanScanJob do
  @moduledoc "Adds a scan job to the transaction that persists its request."

  alias Bolognesa.Libraries.Infrastructure.Jobs.Workers.ScanWorker

  @spec insert(Ecto.Multi.t()) :: Ecto.Multi.t()
  def insert(multi) do
    Oban.insert(multi, :job, fn %{scan: scan} ->
      ScanWorker.new(%{scan_id: scan.id})
    end)
  end
end
