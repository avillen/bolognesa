defmodule Bolognesa.Playback.Infrastructure.TranscodeManager.FfmpegProcess do
  @moduledoc "Start the FFmpeg OS process behind a port and control it with POSIX signals."

  @type action :: :suspend | :resume

  @spec executable() :: {:ok, Path.t()} | {:error, :tool_unavailable}
  def executable do
    case System.find_executable(Application.get_env(:bolognesa, :ffmpeg_executable) || "ffmpeg") do
      nil -> {:error, :tool_unavailable}
      executable -> {:ok, executable}
    end
  end

  @spec open(Path.t(), [String.t()]) :: {:ok, port()} | {:error, :tool_unavailable}
  def open(executable, args) do
    {:ok,
     Port.open({:spawn_executable, executable}, [
       :binary,
       {:line, 1024},
       :exit_status,
       :stderr_to_stdout,
       args: args
     ])}
  rescue
    ArgumentError -> {:error, :tool_unavailable}
    ErlangError -> {:error, :tool_unavailable}
  end

  @spec signal(port(), action()) :: :ok | {:error, :process_missing}
  def signal(port, :suspend), do: kill(port, "STOP")
  def signal(port, :resume), do: kill(port, "CONT")

  @doc "A stopped process cannot handle TERM, so a suspended one is continued first."
  @spec close(port() | nil, boolean()) :: :ok
  def close(nil, _suspended?), do: :ok

  def close(port, suspended?) do
    if suspended?, do: kill(port, "CONT")
    kill(port, "TERM")

    try do
      Port.close(port)
      :ok
    rescue
      ArgumentError -> :ok
    end
  end

  # The slim runtime image has no kill binary (procps), so use the shell builtin.
  defp kill(port, name) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} ->
        {_, status} =
          System.cmd("sh", ["-c", "kill -#{name} \"$1\"", "sh", Integer.to_string(pid)],
            stderr_to_stdout: true
          )

        if status == 0, do: :ok, else: {:error, :process_missing}

      _ ->
        {:error, :process_missing}
    end
  end
end
