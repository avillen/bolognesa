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
    execute(id, attempt, repository, discovery, metadata, System.monotonic_time(:millisecond))
  end

  def perform(_job, _repository, _discovery), do: {:cancel, :unexpected_failure}

  defp execute(id, attempt, repository, discovery, metadata, started) do
    DiscoverFiles.call(id, attempt, repository, discovery)
  rescue
    _exception -> unexpected_failure(metadata, started)
  catch
    _kind, _value -> unexpected_failure(metadata, started)
  end

  defp unexpected_failure(metadata, started) do
    metadata = metadata ++ [duration_ms: max(System.monotonic_time(:millisecond) - started, 0)]
    Logger.warning("Library scan execution failed", [reason: :unexpected_failure] ++ metadata)
    {:error, :unexpected_failure}
  end
end
