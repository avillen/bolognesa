defmodule Bolognesa.Libraries.Infrastructure.Jobs.InspectionWorker do
  @moduledoc "Oban boundary that exposes only safe inspection failure reasons."

  alias Bolognesa.Libraries.Infrastructure.Jobs.InspectionPolicy
  use Oban.Worker, queue: :media_inspections, max_attempts: InspectionPolicy.max_attempts()

  require Logger

  alias Bolognesa.Libraries.Application.UseCases.InspectMediaFile
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoInspectionRepository
  alias Bolognesa.Libraries.Infrastructure.Services.FfprobeMediaProbe

  @impl Oban.Worker
  def timeout(_job), do: InspectionPolicy.timeout_ms()

  @impl Oban.Worker
  def perform(job) do
    probe = Application.get_env(:bolognesa, :media_probe_adapter, FfprobeMediaProbe)
    perform(job, EctoInspectionRepository, probe)
  end

  @spec perform(Oban.Job.t(), module(), module()) :: :ok | {:cancel, atom()} | {:error, atom()}
  def perform(
        %Oban.Job{args: %{"media_file_id" => id, "token" => token}, attempt: attempt} = job,
        repository,
        probe
      )
      when is_integer(id) and id > 0 and is_binary(token) do
    InspectMediaFile.call(id, token, attempt, repository, probe, job.id)
  rescue
    _exception -> unexpected_failure(id, job.id, attempt)
  catch
    _kind, _value -> unexpected_failure(id, job.id, attempt)
  end

  def perform(_job, _repository, _probe), do: {:cancel, :unexpected_failure}

  defp unexpected_failure(id, job_id, attempt) do
    Logger.warning("Technical inspection failed",
      file_id: id,
      job_id: job_id,
      attempt: attempt,
      reason: :unexpected_failure
    )

    {:error, :unexpected_failure}
  end
end
