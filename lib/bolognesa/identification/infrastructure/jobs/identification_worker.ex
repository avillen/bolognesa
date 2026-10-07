defmodule Bolognesa.Identification.Infrastructure.Jobs.IdentificationWorker do
  @moduledoc "Oban boundary for a token protected identification."
  use Oban.Worker, queue: :identifications, max_attempts: 3
  require Logger

  alias Bolognesa.Identification.Application.IdentifyMediaFile
  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository
  alias Bolognesa.Identification.Infrastructure.TmdbMovieProvider

  @impl Oban.Worker
  def timeout(_job), do: 30_000

  @impl Oban.Worker
  def perform(job) do
    provider = Application.get_env(:bolognesa, :movie_provider_adapter, TmdbMovieProvider)
    perform(job, EctoIdentificationRepository, provider)
  end

  @spec perform(Oban.Job.t(), module(), module()) :: :ok | {:error, atom()} | {:cancel, atom()}
  def perform(
        %Oban.Job{args: %{"file_id" => id, "token" => token}, attempt: attempt} = job,
        repository,
        provider
      )
      when is_integer(id) and id > 0 and is_binary(token) do
    IdentifyMediaFile.call(id, token, attempt, repository, provider, job.id)
  rescue
    _ -> unexpected_failure(id, job.id, attempt)
  catch
    _, _ -> unexpected_failure(id, job.id, attempt)
  end

  def perform(_job, _repository, _provider), do: {:cancel, :invalid_job}

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
