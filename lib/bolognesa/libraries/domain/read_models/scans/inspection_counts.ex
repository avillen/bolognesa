defmodule Bolognesa.Libraries.Domain.ReadModels.Scans.InspectionCounts do
  @moduledoc "Counts of available files by technical inspection state."

  alias Bolognesa.Libraries.Domain.Entities.Inspection

  @type t :: %__MODULE__{
          uninspected: non_neg_integer(),
          pending: non_neg_integer(),
          running: non_neg_integer(),
          succeeded: non_neg_integer(),
          failed: non_neg_integer(),
          failure_reasons: %{optional(Inspection.reason()) => non_neg_integer()}
        }

  defstruct uninspected: 0,
            pending: 0,
            running: 0,
            succeeded: 0,
            failed: 0,
            failure_reasons: %{}
end
