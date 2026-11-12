defmodule Bolognesa.Infrastructure.Jobs.PeriodicRunner do
  @moduledoc "Runs a task at startup and again after each configured interval."
  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  @impl true
  def init(opts) do
    state = %{run: Keyword.fetch!(opts, :run), interval_ms: Keyword.fetch!(opts, :interval_ms)}
    {:ok, state, {:continue, :run}}
  end

  @impl true
  def handle_continue(:run, state), do: {:noreply, run(state)}

  @impl true
  def handle_info(:run, state), do: {:noreply, run(state)}

  defp run(state) do
    state.run.()
    Process.send_after(self(), :run, state.interval_ms)
    state
  end
end
