defmodule Bolognesa.Libraries.Infrastructure.Jobs.ScanWorker do
  @moduledoc "Oban boundary that exposes only safe, bounded operational reasons."

  alias Bolognesa.Libraries.Infrastructure.Jobs.ScanPolicy
  use Oban.Worker, queue: :library_scans, max_attempts: ScanPolicy.max_attempts()

  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Libraries.Application.Ports.Repositories.ScanRepository
  alias Bolognesa.Libraries.Application.Ports.Services.{FileDiscovery, LibraryStatusNotifier}
  alias Bolognesa.Libraries.Application.UseCases.DiscoverFiles
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoScanRepository
  alias Bolognesa.Libraries.Infrastructure.Services.LibraryStatusNotifications
  alias Bolognesa.Libraries.Infrastructure.Services.LocalFileDiscovery

  @impl Oban.Worker
  def timeout(_job), do: ScanPolicy.timeout_ms()

  @impl Oban.Worker
  def perform(job), do: perform(job, EctoScanRepository, LocalFileDiscovery)

  @doc "Runs the same safe boundary with explicit port adapters, including controlled integrations."
  @spec perform(
          Oban.Job.t(),
          ScanRepository.adapter(),
          FileDiscovery.adapter(),
          LibraryStatusNotifier.adapter()
        ) ::
          DiscoverFiles.result()
  def perform(job, repository, discovery, notifications \\ LibraryStatusNotifications)

  def perform(
        %Oban.Job{args: %{"scan_id" => id}, attempt: attempt} = job,
        repository,
        discovery,
        notifications
      )
      when is_integer(id) and id > 0 do
    metadata = [scan_id: id, job_id: job.id, attempt: attempt]

    execute(
      id,
      attempt,
      repository,
      discovery,
      notifications,
      metadata,
      System.monotonic_time(:millisecond)
    )
  end

  def perform(_job, _repository, _discovery, _notifications), do: {:cancel, :unexpected_failure}

  defp execute(id, attempt, repository, discovery, notifications, metadata, started) do
    DiscoverFiles.call(id, attempt, repository, discovery, notifications, metadata[:job_id])
  rescue
    _exception -> unexpected_failure(metadata, started)
  catch
    _kind, _value -> unexpected_failure(metadata, started)
  end

  defp unexpected_failure(metadata, started) do
    Events.emit(:libraries, :scan, :failed, Map.new([reason: :unexpected_failure] ++ metadata), %{
      duration_ms: Events.elapsed(started)
    })

    {:error, :unexpected_failure}
  end
end
