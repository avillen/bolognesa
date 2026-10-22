defmodule Bolognesa.Series.Infrastructure.Jobs.IdentificationReconciler do
  @moduledoc "Marks pending identifications whose jobs ended without a result."
  use GenServer
  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Series.Application.UseCases.ReconcileIdentificationJobs

  alias Bolognesa.Series.Infrastructure.Repositories.EctoIdentificationRepository

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts),
    do: %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}

  @impl true
  def init(opts) do
    state = %{
      repository: Keyword.get(opts, :repository, EctoIdentificationRepository),
      interval_ms: Keyword.get(opts, :interval_ms, 60_000)
    }

    {:ok, state, {:continue, :reconcile}}
  end

  @impl true
  def handle_continue(:reconcile, state), do: {:noreply, run(state)}

  @impl true
  def handle_info(:reconcile, state), do: {:noreply, run(state)}

  defp run(state) do
    ReconcileIdentificationJobs.call(DateTime.utc_now(), state.repository)

    Process.send_after(self(), :reconcile, state.interval_ms)
    state
  rescue
    _ ->
      Events.emit(:series, :reconciliation, :failed, %{
        reason: :unexpected_failure,
        failure_stage: :recovery
      })

      Process.send_after(self(), :reconcile, state.interval_ms)
      state
  end
end
