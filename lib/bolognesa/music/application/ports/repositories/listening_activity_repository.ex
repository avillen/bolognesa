defmodule Bolognesa.Music.Application.Ports.Repositories.ListeningActivityRepository do
  @moduledoc "Persists the latest qualifying listening activity."
  @type adapter :: module()
  @callback record(pos_integer(), pos_integer()) :: :ok | {:error, :unavailable}
end
