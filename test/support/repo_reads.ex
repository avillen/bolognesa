defmodule Bolognesa.RepoReads do
  @moduledoc """
  Observes repo reads made on behalf of the calling test, such as LiveView async tasks.

  Each matching read sends `{:read, reader_pid, params}` to the test. Reads accepted by
  `park?` wait inside their process until the test sends `:continue` to the reader.
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
    after
      @park_timeout -> :ok
    end
  end
end
