defmodule Bolognesa.Movies.Infrastructure.Jobs.IdentificationReconciler do
  @moduledoc "Marks pending identifications whose jobs ended without a result."
  alias Bolognesa.Infrastructure.Jobs.PeriodicRunner
  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Movies.Application.UseCases.ReconcileIdentificationJobs

  alias Bolognesa.Movies.Infrastructure.Repositories.EctoIdentificationRepository

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    repository = Keyword.get(opts, :repository, EctoIdentificationRepository)

    PeriodicRunner.start_link(
      name: Keyword.get(opts, :name, __MODULE__),
      interval_ms: Keyword.get(opts, :interval_ms, 60_000),
      run: fn -> run(repository) end
    )
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts),
    do: %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}

  defp run(repository) do
    ReconcileIdentificationJobs.call(DateTime.utc_now(), repository)
  rescue
    _ ->
      Events.emit(:movies, :reconciliation, :failed, %{
        reason: :unexpected_failure,
        failure_stage: :recovery
      })
  end
end
