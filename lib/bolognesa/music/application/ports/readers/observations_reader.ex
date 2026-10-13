defmodule Bolognesa.Music.Application.Ports.Readers.ObservationsReader do
  @moduledoc "Read current successful music observations."
  alias Bolognesa.Music.Domain.ValueObjects.Observation
  @type adapter :: atom()
  @type result :: {:ok, Observation.t() | :stale} | {:error, :unavailable}
  @callback current(file_id :: pos_integer(), revision :: pos_integer()) :: result()
end
