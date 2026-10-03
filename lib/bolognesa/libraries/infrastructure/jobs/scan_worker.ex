defmodule Bolognesa.Libraries.Infrastructure.Jobs.ScanWorker do
  @moduledoc "Oban boundary that exposes only safe, bounded operational reasons."

  alias Bolognesa.Libraries.Infrastructure.Jobs.ScanPolicy
  use Oban.Worker, queue: :library_scans, max_attempts: ScanPolicy.max_attempts()

  require Logger
  alias Bolognesa.Libraries.Application.DiscoverFiles
  alias Bolognesa.Libraries.Application.Ports.{FileDiscovery, ScanRepository}
  alias Bolognesa.Libraries.Infrastructure.LocalFileDiscovery
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository

  @impl Oban.Worker
  def timeout(_job), do: ScanPolicy.timeout_ms()

  @impl Oban.Worker
  def perform(job), do: perform(job, EctoScanRepository, LocalFileDiscovery)

  @doc "Runs the same safe boundary with explicit port adapters, including controlled integrations."
  @spec perform(Oban.Job.t(), ScanRepository.adapter(), FileDiscovery.adapter()) ::
          DiscoverFiles.result()
  def perform(%Oban.Job{args: %{"scan_id" => id}, attempt: attempt} = job, repository, discovery)
      when is_integer(id) and id > 0 do
    metadata = [scan_id: id, job_id: job.id, attempt: attempt]
    Logger.info("Library scan started", metadata)
    result = execute(id, attempt, repository, discovery)
    log_result(result, metadata)
    result
  end

  def perform(_job, _repository, _discovery), do: {:cancel, :unexpected_failure}

  defp execute(id, attempt, repository, discovery) do
    DiscoverFiles.call(id, attempt, repository, discovery)
  rescue
    _exception -> {:error, :unexpected_failure}
  catch
    _kind, _value -> {:error, :unexpected_failure}
  end

  defp log_result(:ok, metadata), do: Logger.info("Library scan finished", metadata)

  defp log_result({:cancel, reason}, metadata),
    do: Logger.error("Library scan failed", [reason: reason] ++ metadata)

  defp log_result({:error, reason}, metadata),
    do: Logger.warning("Library scan execution failed", [reason: reason] ++ metadata)
end
