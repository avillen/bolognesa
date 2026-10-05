defmodule Bolognesa.Libraries.Support.BlockingMediaProbe do
  @moduledoc false
  @behaviour Bolognesa.Libraries.Application.Ports.MediaProbe

  alias Bolognesa.Libraries.Support.SuccessfulMediaProbe

  @impl true
  def inspect(library, file) do
    send(Process.whereis(:inspection_probe_owner), {:probe_started, self()})

    receive do
      :probe_continue -> SuccessfulMediaProbe.inspect(library, file)
    end
  end
end
