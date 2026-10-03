defmodule Bolognesa.Libraries.Infrastructure.Jobs.ScanPolicy do
  @moduledoc "Bounded execution and recovery budgets for the single scan queue."

  @spec timeout_ms() :: pos_integer()
  def timeout_ms, do: 600_000

  @spec rescue_after_ms() :: pos_integer()
  def rescue_after_ms, do: 900_000

  @spec reconcile_interval_ms() :: pos_integer()
  def reconcile_interval_ms, do: 60_000

  @spec max_attempts() :: pos_integer()
  def max_attempts, do: 3

  @spec batch_size() :: pos_integer()
  def batch_size, do: 100
end
