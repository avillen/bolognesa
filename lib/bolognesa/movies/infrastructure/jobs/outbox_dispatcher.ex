defmodule Bolognesa.Movies.Infrastructure.Jobs.OutboxDispatcher do
  @moduledoc "Delivers persisted identification requests to Oban."
  use GenServer
  require Logger

  alias Bolognesa.Movies.Infrastructure.Repositories.EctoOutboxRepository

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
      repository: Keyword.get(opts, :repository, EctoOutboxRepository),
      interval_ms: Keyword.get(opts, :interval_ms, 5_000),
      batch_size: Keyword.get(opts, :batch_size, 100)
    }

    {:ok, state, {:continue, :dispatch}}
  end

  @impl true
  def handle_continue(:dispatch, state), do: {:noreply, dispatch_and_schedule(state)}

  @impl true
  def handle_info(:dispatch, state), do: {:noreply, dispatch_and_schedule(state)}

  defp dispatch_and_schedule(state) do
    run(state.repository, state.batch_size)
    Process.send_after(self(), :dispatch, state.interval_ms)
    state
  end

  defp run(repository, batch_size) do
    case repository.dispatch_batch(batch_size) do
      {:ok, _count} ->
        :ok

      {:error, :unavailable} ->
        Logger.warning("Identification outbox unavailable", reason: :storage_unavailable)
    end
  rescue
    _exception -> Logger.error("Identification outbox failed", reason: :unexpected_failure)
  catch
    _kind, _value -> Logger.error("Identification outbox failed", reason: :unexpected_failure)
  end
end
