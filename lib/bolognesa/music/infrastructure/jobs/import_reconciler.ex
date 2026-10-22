defmodule Bolognesa.Music.Infrastructure.Jobs.ImportReconciler do
  @moduledoc "Restores visible music import state after job interruption."
  use GenServer
  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Music.Application.UseCases.ReconcileImports
  alias Bolognesa.Music.Infrastructure.Repositories.EctoImportRepository
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts),
    do: %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}

  @impl true
  def init(opts),
    do: {:ok, %{interval: Keyword.get(opts, :interval_ms, 30_000)}, {:continue, :reconcile}}

  @impl true
  def handle_continue(:reconcile, state), do: {:noreply, run(state)}

  @impl true
  def handle_info(:reconcile, state), do: {:noreply, run(state)}

  defp run(state) do
    reconcile()

    Process.send_after(self(), :reconcile, state.interval)
    state
  end

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
