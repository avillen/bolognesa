defmodule Bolognesa.Music.Infrastructure.Jobs.ImportPolicy do
  @moduledoc "Bounded music import operational budgets."
  @spec max_attempts() :: pos_integer()
  def max_attempts, do: 3
  @spec timeout_ms() :: pos_integer()
  def timeout_ms, do: 30_000
end
