defmodule Bolognesa.Series.Infrastructure.Jobs.Workers.IdentificationWorker do
  @moduledoc "Runs a token-protected series identification."
  use Oban.Worker, queue: :identifications, max_attempts: 3
  alias Bolognesa.Infrastructure.Jobs.IdentificationJob
  alias Bolognesa.Series.Application.Ports.Providers.SeriesProvider
  alias Bolognesa.Series.Application.Ports.Repositories.IdentificationRepository
  alias Bolognesa.Series.Application.UseCases.IdentifySeriesFile
  alias Bolognesa.Series.Infrastructure.Providers.TmdbSeriesProvider
  alias Bolognesa.Series.Infrastructure.Repositories.EctoIdentificationRepository

  @impl Oban.Worker
  def timeout(_job), do: 30_000

  @impl Oban.Worker
  def perform(job),
    do:
      perform(
        job,
        EctoIdentificationRepository,
        Application.get_env(:bolognesa, :series_provider_adapter, TmdbSeriesProvider)
      )

  @spec perform(Oban.Job.t(), IdentificationRepository.adapter(), SeriesProvider.adapter()) ::
          :ok
          | {:error, IdentificationRepository.reason() | SeriesProvider.reason()}
          | {:cancel, :invalid_job}
  def perform(job, repository, provider) do
    IdentificationJob.perform(job, :series, fn id, token, attempt ->
      IdentifySeriesFile.call(id, token, attempt, repository, provider, job.id)
    end)
  end
end
