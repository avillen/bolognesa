defmodule Bolognesa.Libraries.Support.TimeoutMediaProbe do
  @moduledoc false
  @behaviour Bolognesa.Libraries.Application.Ports.Services.MediaProbe

  @impl true
  def inspect(_library, _file), do: {:error, :timeout}
end
