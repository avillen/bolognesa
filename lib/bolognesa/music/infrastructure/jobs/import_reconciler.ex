defmodule Bolognesa.Music.Infrastructure.Jobs.ImportReconciler do
  @moduledoc "Restores visible music import state after job interruption."
  alias Bolognesa.Infrastructure.Jobs.PeriodicRunner
  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Music.Application.UseCases.ReconcileImports
  alias Bolognesa.Music.Infrastructure.Repositories.EctoImportRepository
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    PeriodicRunner.start_link(
      name: Keyword.get(opts, :name, __MODULE__),
      interval_ms: Keyword.get(opts, :interval_ms, 30_000),
      run: &reconcile/0
    )
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts),
    do: %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}

  defp reconcile do
    ReconcileImports.call(DateTime.utc_now(), EctoImportRepository)
  rescue
    _error -> unexpected()
  catch
    _kind, _value -> unexpected()
  end

  defp unexpected,
    do:
      Events.emit(:music, :reconciliation, :failed, %{
        reason: :unexpected_failure,
        failure_stage: :recovery
      })
end
