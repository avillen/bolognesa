defmodule Bolognesa.Infrastructure.Observability.Observation do
  @moduledoc "Carries diagnostic metadata and monotonic timing without interpreting outcomes."

  alias Bolognesa.Infrastructure.Observability.Events

  @type t :: {map(), integer()}

  @spec start(map()) :: t()
  def start(metadata), do: {metadata, Events.started_at()}

  @spec put(t(), atom(), integer() | atom()) :: t()
  def put({metadata, started}, key, value), do: {Map.put(metadata, key, value), started}

  @spec emit(t(), Events.context(), Events.resource(), Events.outcome(), map()) :: :ok
  def emit({metadata, started}, context, resource, outcome, additional \\ %{}) do
    Events.emit(context, resource, outcome, Map.merge(metadata, additional), %{
      duration_ms: Events.elapsed(started)
    })
  end
end
