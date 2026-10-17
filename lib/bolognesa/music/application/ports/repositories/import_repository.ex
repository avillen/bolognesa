defmodule Bolognesa.Music.Application.Ports.Repositories.ImportRepository do
  @moduledoc "Recoverable import attempts and authorized retry persistence."
  alias Bolognesa.Music.Domain.Entities.ImportState
  @type adapter :: atom()
  @type failure :: ImportState.failure_reason()
  @callback request_retry(file_id :: pos_integer()) :: :ok | {:error, :not_found | :unavailable}
  @callback begin_attempt(
              file_id :: pos_integer(),
              revision :: pos_integer(),
              job_id :: pos_integer()
            ) :: {:ok, ImportState.t() | :stale} | {:error, :unavailable}
  @callback fail_attempt(ImportState.t(), failure()) ::
              :ok | {:ok, :stale} | {:error, :unavailable}
  @callback reconcile_jobs(DateTime.t()) :: :ok | {:error, :unavailable}
end
