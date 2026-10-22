defmodule Bolognesa.Music.Application.Ports.Repositories.ImportRepository do
  @moduledoc "Recoverable import attempts and authorized retry persistence."
  alias Bolognesa.Music.Domain.Entities.ImportState
  @type adapter :: atom()
  @type recovery_summary :: %{recovered_count: non_neg_integer(), library_ids: [pos_integer()]}
  @type failure :: ImportState.failure_reason()
  @callback request_retry(file_id :: pos_integer()) :: :ok | {:error, :not_found | :unavailable}
  @callback request_retry_with_result(file_id :: pos_integer()) ::
              {:ok, :requested | :unchanged} | {:error, :not_found | :unavailable}
  @callback begin_attempt(
              file_id :: pos_integer(),
              revision :: pos_integer(),
              job_id :: pos_integer()
            ) :: {:ok, ImportState.t() | :stale} | {:error, :unavailable}
  @callback fail_attempt(ImportState.t(), failure()) ::
              :ok | {:ok, :stale} | {:error, :unavailable}
  @callback reconcile_jobs(DateTime.t()) :: :ok | {:error, :unavailable}
  @callback reconcile_jobs_with_summary(DateTime.t()) ::
              {:ok, recovery_summary()} | {:error, :unavailable, recovery_summary()}
end
