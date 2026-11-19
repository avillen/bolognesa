defmodule Bolognesa.Infrastructure.Jobs.IdentificationReconciler do
  @moduledoc "Marks pending identifications whose jobs ended without a result."
  alias Bolognesa.Infrastructure.Jobs.PeriodicRunner
  alias Bolognesa.Infrastructure.Observability.Events

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    context = Keyword.fetch!(opts, :context)
    use_case = Keyword.fetch!(opts, :use_case)
    repository = Keyword.fetch!(opts, :repository)

    PeriodicRunner.start_link(
      name: Keyword.fetch!(opts, :name),
      interval_ms: Keyword.get(opts, :interval_ms, 60_000),
      run: fn -> run(context, use_case, repository) end
    )
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts),
    do: %{id: Keyword.fetch!(opts, :name), start: {__MODULE__, :start_link, [opts]}}

  defp run(context, use_case, repository) do
    use_case.call(DateTime.utc_now(), repository)
  rescue
    _ ->
      Events.emit(context, :reconciliation, :failed, %{
        reason: :unexpected_failure,
        failure_stage: :recovery
      })
  end
end
