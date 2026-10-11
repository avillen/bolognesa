defmodule Bolognesa.Libraries.Support.FailingMediaProbe do
  @moduledoc false
  @behaviour Bolognesa.Libraries.Application.Ports.Services.MediaProbe

  @impl true
  def inspect(_library, _file), do: {:error, :invalid_output}
end
