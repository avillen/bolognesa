defmodule Bolognesa.Libraries.Infrastructure.Jobs.InspectionReconciler do
  @moduledoc "Resolves technical inspections left unfinished by terminal or lost jobs."
  use GenServer
  require Logger

  alias Bolognesa.Libraries.Infrastructure.Jobs.InspectionPolicy
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoInspectionRepository

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}
  end

  @impl true
  def init(opts) do
    state = %{
      repository: Keyword.get(opts, :repository, EctoInspectionRepository),
      interval_ms: Keyword.get(opts, :interval_ms, InspectionPolicy.reconcile_interval_ms())
    }

    {:ok, state, {:continue, :reconcile}}
  end

  @impl true
  def handle_continue(:reconcile, state), do: {:noreply, reconcile_and_schedule(state)}

  @impl true
  def handle_info(:reconcile, state), do: {:noreply, reconcile_and_schedule(state)}

  defp reconcile_and_schedule(state) do
    run(state.repository)
    Process.send_after(self(), :reconcile, state.interval_ms)
    state
  end

  defp run(repository) do
    case repository.reconcile_jobs(DateTime.utc_now()) do
      :ok ->
        :ok

      {:error, :unavailable} ->
        Logger.warning("Technical inspection reconciliation unavailable",
          reason: :storage_unavailable
        )
    end
  rescue
    _exception ->
      Logger.error("Technical inspection reconciliation failed", reason: :unexpected_failure)
  catch
    _kind, _value ->
      Logger.error("Technical inspection reconciliation failed", reason: :unexpected_failure)
  end
end
