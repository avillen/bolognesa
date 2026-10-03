defmodule Bolognesa.Libraries.Application.Ports.FileDiscovery do
  @moduledoc "Read-only file discovery, validating the source before and after all batches."

  alias Bolognesa.Libraries.Domain.NewMediaFile

  @type adapter :: atom()
  @type error ::
          :source_inaccessible
          | :source_outside_roots
          | :source_changed
          | :entry_unreadable
          | :unsafe_entry
          | :stale_attempt
          | :unavailable
  @type sink :: ([NewMediaFile.t()] -> :ok | {:error, error()})

  @doc "A failed final validation must not authorize scan completion."
  @callback walk(String.t(), sink()) :: :ok | {:error, error()}
end
