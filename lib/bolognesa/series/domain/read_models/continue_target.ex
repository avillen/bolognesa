defmodule Bolognesa.Series.Domain.ReadModels.ContinueTarget do
  @moduledoc "The entry a series page offers to start, continue or replay."
  alias Bolognesa.Series.Domain.ReadModels.EntryStatus

  @type action :: :start | :continue | :replay
  @type t :: %__MODULE__{action: action(), entry: EntryStatus.t()}
  @enforce_keys [:action, :entry]
  defstruct [:action, :entry]
end
