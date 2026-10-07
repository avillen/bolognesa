defmodule Bolognesa.Identification.Infrastructure.Jobs.IdentificationReconciler do
  @moduledoc "Marks pending identifications whose jobs ended without a result."
  use GenServer
  require Logger

  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository

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
    case state.repository.reconcile_jobs(DateTime.utc_now()) do
      :ok ->
        :ok

      {:error, :unavailable} ->
        Logger.warning("Identification reconciliation unavailable", reason: :storage_unavailable)
    end

    Process.send_after(self(), :reconcile, state.interval_ms)
    state
  rescue
    _ ->
      Logger.warning("Identification reconciliation failed", reason: :unexpected_failure)
      Process.send_after(self(), :reconcile, state.interval_ms)
      state
  end
end
