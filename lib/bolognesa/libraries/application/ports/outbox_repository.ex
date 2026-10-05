defmodule Bolognesa.Libraries.Application.Ports.OutboxRepository do
  @moduledoc "Persistence boundary for durable inspection event delivery."

  @type adapter :: module()
  @callback dispatch_batch(pos_integer()) :: {:ok, non_neg_integer()} | {:error, :unavailable}
end
