defmodule Bolognesa.Libraries.Application.Ports.Repositories.MusicRefreshOutboxRepository do
  @moduledoc "Durable handoff of music inspections to refresh jobs."
  @type adapter :: atom()
  @callback dispatch_batch(pos_integer()) :: {:ok, non_neg_integer()} | {:error, :unavailable}
end
