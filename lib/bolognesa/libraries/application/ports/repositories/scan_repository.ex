defmodule Bolognesa.Libraries.Application.Ports.Repositories.ScanRepository do
  @moduledoc "Durable scan requests, generation-protected inventory writes and recovery."

  alias Bolognesa.Libraries.Domain.{Library, NewMediaFile, Scan, ScanStatus}

  @type adapter :: atom()

  @callback request(Library.id()) ::
              {:ok, Scan.t()} | {:error, :not_found | :scan_in_progress | :unavailable}
  @callback request(Library.id(), boolean()) ::
              {:ok, Scan.t()} | {:error, :not_found | :scan_in_progress | :unavailable}
  @callback status(Library.id()) ::
              {:ok, ScanStatus.t()} | {:error, :not_found | :unavailable}
  @callback begin_attempt(Scan.id(), pos_integer()) ::
              {:ok, Scan.t(), Library.t()}
              | {:ok, :terminal}
              | {:error, :not_found | :unavailable}
  @callback save_batch(Scan.id(), Scan.generation(), [NewMediaFile.t()]) ::
              {:ok, Scan.t()} | {:error, :stale_attempt | :unavailable}
  @callback complete(Scan.id(), Scan.generation()) ::
              {:ok, Scan.t()} | {:error, :stale_attempt | :unavailable}
  @callback fail(Scan.id(), Scan.generation(), Scan.reason(), :retrying | :failed) ::
              :ok | {:error, :stale_attempt | :unavailable}
  @callback reconcile_jobs(DateTime.t()) :: :ok | {:error, :unavailable}
end
