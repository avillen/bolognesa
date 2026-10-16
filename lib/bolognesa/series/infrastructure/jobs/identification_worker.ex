defmodule Bolognesa.Series.Infrastructure.Jobs.IdentificationWorker do
  @moduledoc "Runs a token-protected series identification."
  use Oban.Worker, queue: :identifications, max_attempts: 3
  require Logger
  alias Bolognesa.Series.Application.Ports.Providers.SeriesProvider
  alias Bolognesa.Series.Application.Ports.Repositories.IdentificationRepository
  alias Bolognesa.Series.Application.UseCases.IdentifySeriesFile

  @impl Oban.Worker
  def timeout(_job), do: 30_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"file_id" => id, "token" => token}, attempt: attempt} = job)
      when is_integer(id) and id > 0 and is_binary(token) do
    Bolognesa.Series.identify_file(id, token, attempt, job.id)
  rescue
    _ -> unexpected_failure(id, job.id, attempt)
  catch
    _, _ -> unexpected_failure(id, job.id, attempt)
  end

  def perform(_), do: {:cancel, :invalid_job}

  @spec perform(Oban.Job.t(), IdentificationRepository.adapter(), SeriesProvider.adapter()) ::
          :ok | {:error, atom()} | {:cancel, :invalid_job}
  def perform(
        %Oban.Job{args: %{"file_id" => id, "token" => token}, attempt: attempt} = job,
        repository,
        provider
      )
      when is_integer(id) and id > 0 and is_binary(token) do
    IdentifySeriesFile.call(id, token, attempt, repository, provider, job.id)
  rescue
    _ -> unexpected_failure(id, job.id, attempt)
  catch
    _, _ -> unexpected_failure(id, job.id, attempt)
  end

  def perform(_, _, _), do: {:cancel, :invalid_job}

  defp unexpected_failure(id, job_id, attempt) do
    Logger.warning("Identification job failed",
      file_id: id,
      job_id: job_id,
      attempt: attempt,
      reason: :unexpected_failure
    )

    {:error, :unexpected_failure}
  end
end
