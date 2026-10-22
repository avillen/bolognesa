defmodule Bolognesa.Music.Application.UseCases.ReconcileImports do
  @moduledoc "Observe committed import recovery without reporting idle polling."
  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Music.Application.Ports.Repositories.ImportRepository

  @spec call(DateTime.t(), ImportRepository.adapter()) :: :ok | {:error, :unavailable}
  def call(now, repository) do
    started = Events.started_at()
    repository.reconcile_jobs_with_summary(now) |> observe(started)
  end

  defp observe({:ok, summary}, started) do
    recovered(summary, started)
    :ok
  end

  defp observe({:error, :unavailable, summary}, started) do
    recovered(summary, started)

    Events.emit(
      :music,
      :reconciliation,
      :retryable,
      %{reason: :storage_unavailable, failure_stage: :recovery},
      measurements(summary, started)
    )

    {:error, :unavailable}
  end

  defp recovered(%{recovered_count: 0}, _started), do: :ok

  defp recovered(summary, started),
    do: Events.emit(:music, :reconciliation, :recovered, %{}, measurements(summary, started))

  defp measurements(summary, started),
    do: %{
      recovered_count: summary.recovered_count,
      changed_library_count: length(summary.library_ids),
      duration_ms: Events.elapsed(started)
    }
end
