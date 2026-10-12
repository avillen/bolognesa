defmodule Bolognesa.Libraries.Domain.ReadModels.ReconciliationResult do
  @moduledoc "Confirmed changes retained even when a later recovery transaction fails."

  alias Bolognesa.Libraries.Domain.Entities.Library

  defstruct changed_library_ids: [], error: nil

  @type t :: %__MODULE__{
          changed_library_ids: [Library.id()],
          error: nil | :unavailable
        }
end
