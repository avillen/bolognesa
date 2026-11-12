defmodule Bolognesa.Music.Application.Ports.Repositories.ListeningActivityRepository do
  @moduledoc "Persists the latest qualifying listening activity."
  alias Bolognesa.Music.Domain.Entities.Track

  @type adapter :: atom()
  @callback record(user_id :: pos_integer(), Track.id()) :: :ok | {:error, :unavailable}
end
