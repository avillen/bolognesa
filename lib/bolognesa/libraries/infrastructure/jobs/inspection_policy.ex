defmodule Bolognesa.Libraries.Infrastructure.Jobs.InspectionPolicy do
  @moduledoc "Execution and recovery budgets for technical inspections."

  alias Bolognesa.Libraries.Domain.Entities.Inspection

  @spec max_attempts() :: pos_integer()
  def max_attempts, do: Inspection.max_attempts()

  @spec timeout_ms() :: pos_integer()
  def timeout_ms, do: 45_000

  @spec rescue_after_ms() :: pos_integer()
  def rescue_after_ms, do: 90_000

  @spec reconcile_interval_ms() :: pos_integer()
  def reconcile_interval_ms, do: 60_000
end
