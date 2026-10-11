defmodule Bolognesa.Libraries.Support.ControlledFileDiscovery do
  @moduledoc false
  @behaviour Bolognesa.Libraries.Application.Ports.Services.FileDiscovery

  @spec configure(pid()) :: :ok
  def configure(owner) do
    Process.put(__MODULE__, owner)
    :ok
  end

  @impl true
  def walk(_path, sink) do
    owner = Process.get(__MODULE__)
    send(owner, {:walking, self()})
    consume(owner, sink)
  end

  defp consume(owner, sink) do
    receive do
      {:batch, entries} ->
        result = sink.(entries)
        send(owner, {:batch_result, self(), result})
        continue(result, owner, sink)

      {:finish, result} ->
        result

      {:raise, exception} ->
        raise exception

      {:throw, value} ->
        throw(value)

      {:exit, value} ->
        exit(value)
    end
  end

  defp continue(:ok, owner, sink), do: consume(owner, sink)
  defp continue(error, _owner, _sink), do: error
end
