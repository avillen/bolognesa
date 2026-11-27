defmodule Bolognesa.RepoReads do
  @moduledoc """
  Observes repo reads made on behalf of the calling test, such as LiveView async tasks.

  Each matching read sends `{:read, reader_pid, params}` to the test. Reads accepted by
  `park?` wait inside their process until the test releases them with `:continue` or
  fails them with `fail_read/1`.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  @park_timeout 10_000

  @spec watch_reads((String.t(), list() -> boolean()), (list() -> boolean())) :: :ok
  def watch_reads(match?, park?) do
    handler = {__MODULE__, make_ref()}
    test = self()

    :ok =
      :telemetry.attach(
        handler,
        [:bolognesa, :repo, :query],
        fn _, _, %{query: query, params: params}, _ ->
          report(test, match?, park?, query, params)
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  @doc "Ends a parked read as a crashed read, which a LiveView reports to `handle_async/3`."
  @spec fail_read(pid()) :: :ok
  def fail_read(reader) do
    send(reader, :fail)
    :ok
  end

  defp report(test, match?, park?, query, params) do
    # Only reads started from this test's processes, never another test's or app's.
    if test in Process.get(:"$callers", []) and match?.(query, params) do
      send(test, {:read, self(), params})
      if park?.(params), do: park()
    end
  end

  defp park do
    receive do
      :continue -> :ok
      :fail -> crash()
    after
      @park_timeout -> :ok
    end
  end

  # A raising async task unlinks before it exits; a linked exit would take the LiveView down too.
  defp crash do
    {:links, links} = Process.info(self(), :links)
    Enum.each(links, &Process.unlink/1)
    Process.exit(self(), :read_failed)
  end
end
