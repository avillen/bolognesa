defmodule Bolognesa.Libraries.Infrastructure.Services.BoundedCommand do
  @moduledoc "Runs an executable without a shell, bounding wall time and captured output."

  @spec run(binary(), [binary()], pos_integer(), pos_integer()) ::
          {:ok, binary()} | {:error, :timeout | :too_large | :tool_unavailable | :failed}
  def run(executable, args, timeout_ms, max_bytes)
      when is_binary(executable) and is_list(args) and timeout_ms > 0 and max_bytes > 0 do
    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: args
      ])

    deadline = System.monotonic_time(:millisecond) + timeout_ms
    collect(port, deadline, max_bytes, [], 0)
  rescue
    ArgumentError -> {:error, :tool_unavailable}
    ErlangError -> {:error, :tool_unavailable}
  end

  defp collect(port, deadline, max_bytes, chunks, size) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} ->
        new_size = size + byte_size(data)

        if new_size > max_bytes do
          stop(port)
          {:error, :too_large}
        else
          collect(port, deadline, max_bytes, [data | chunks], new_size)
        end

      {^port, {:exit_status, 0}} ->
        {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary()}

      {^port, {:exit_status, _}} ->
        {:error, :failed}
    after
      remaining ->
        stop(port)
        {:error, :timeout}
    end
  end

  # Port.close/1 only closes the pipes; the OS process would keep reading the file.
  defp stop(port) do
    with {:os_pid, pid} <- Port.info(port, :os_pid) do
      System.cmd("sh", ["-c", "kill -KILL \"$1\" 2>/dev/null", "sh", Integer.to_string(pid)])
    end

    Port.close(port)
  rescue
    # The process may have exited while it was being killed.
    ArgumentError -> true
  end
end
