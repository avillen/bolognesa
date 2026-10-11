defmodule Bolognesa.Libraries.Support.RaisingMediaProbe do
  @moduledoc false
  @behaviour Bolognesa.Libraries.Application.Ports.Services.MediaProbe

  @impl true
  def inspect(_library, _file), do: raise("private /media/film.mkv data")
end
