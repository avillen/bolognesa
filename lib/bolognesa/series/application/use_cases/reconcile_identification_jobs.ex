defmodule Bolognesa.Series.Application.UseCases.ReconcileIdentificationJobs do
  @moduledoc "Observe committed recovery changes, retaining partial results."
  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Series.Application.Ports.Repositories.IdentificationRepository

  @spec call(DateTime.t(), IdentificationRepository.adapter()) :: :ok | {:error, :unavailable}
  def call(now, repository) do
    started = Events.started_at()

    case repository.reconcile_jobs_result(now) do
      {:ok, 0} ->
        :ok

      {:ok, count} ->
        Events.emit(:series, :reconciliation, :recovered, %{}, %{
          recovered_count: count,
          duration_ms: Events.elapsed(started)
        })

        :ok

      {:error, :unavailable, count} ->
        Events.emit(:series, :reconciliation, :failed, %{reason: :storage_unavailable}, %{
          recovered_count: count,
          duration_ms: Events.elapsed(started)
        })

        {:error, :unavailable}
    end
  end
end
